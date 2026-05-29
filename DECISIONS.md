# DECISIONS.md

Architectural Decision Records for mosko-fintech. Each entry captures a non-obvious choice: what was decided, what was considered, why.

## Format

mosko-fintech uses **two ADR patterns** per the policy locked at ADR-009 Decision 8. The pattern fits the decision shape; both patterns are first-class.

### Consolidation pattern

Used for: synthesis work, canonical-reference layers, multi-Decision territory establishment. Examples: ADR-002, ADR-008, ADR-009.

**Structure:**

- **Date** / **Status** / **Phase** preamble
- **Context** — multi-paragraph framing of what surfaces the ADR and what's at stake
- **Decisions** — numbered subjects (`### Decision 1 — <title>`, `### Decision 2 — <title>`, etc.), each with structured content (decision itself + rationale + alternatives considered + cross-references)
- **Consequences** — downstream phase implications, pending tasks, supersession notes, ADR housekeeping

### Terse pattern

Used for: one-off decisions, simple supersessions, isolated choices that don't warrant consolidation ceremony.

**Structure:**

```
### YYYY-MM-DD — <short decision title>
**Decision:** <one sentence>
**Why:** <one or two sentences>
**Alternatives considered:** <bullets>
**Approved by:** <name>
**Supersedes:** <ref to prior decision, if any>
```

### Common conventions (apply to both patterns)

- **One ADR per H2 heading**, numbered sequentially.
- **Newest at top** (this file is read by scrolling down through history).
- **Immutable once accepted.** Supersede via a new entry rather than rewriting an old one. Status values: `Proposed`, `Accepted`, `Superseded by ADR-NNN`, `Deprecated`.
- **Cross-references** to other ADRs use `ADR-NNN` (e.g., "supersedes ADR-005"). Cross-references to PRD / WORKFLOW / SECURITY use anchor refs (e.g., `docs/PRD/index.html#sec-4-5`, `docs/SECURITY/index.html#rt-13`).

---

## ADR-014 — Phase 2 design system: foundation, two-tier tokens, and the `docs/DESIGN/` home

**Date:** 2026-05-29
**Status:** Accepted
**Phase:** 2 (Steps 6–9 — UX→Visual handoff, palette/typography/dark checkpoint, design-system spec, token taxonomy; consumes [ADR-013](#adr-013) flows + decisions; Step 10 tokens-as-code remains gated on the Phase-3 frontend-framework choice per [ADR-012](#adr-012))

**Context.** With the §2 flows locked + the P1–P6 walk-through decisions in [ADR-013](#adr-013), Phase 2 proceeded through wireframes (Step 4, low-fi HTML), the UX→Visual handoff (Step 5; ~45 screens + a consolidated component inventory incl. INV-3: breadcrumb / action-menu / chart-granularity chip-group), the mandatory palette/typography/dark-mode checkpoint (Step 7), the full design-system spec applied across all 6 clusters (Step 8), and the token taxonomy (Step 9). **Output format = HTML route** (F/CTO call): the Visual Designer applies real palette/type/spacing to the wireframe HTML, reviewed in-browser; CSS custom properties serve as the framework-agnostic token layer (the ADR-012 intermediate). **Figma MCP is connected as the escalation path** if HTML proved insufficient (it didn't). **No Claude Design (claude.ai/design) bridge exists from Claude Code** — it's a browser-only interactive tool with no MCP/API (confirmed via the Anthropic announcement + this session's tooling), so it was not usable for agent-driven design here. Working artifacts (the live palette switcher, walkthrough decks, the decisions log) live in gitignored `temp/`; this ADR is the committed decision record.

**Decisions.**

### Decision 1 — Visual foundation (locked at the Step 7 checkpoint)
- **Palette = Restrained Semantic (B), refined.** Semantic green/red (`--c-pos`/`--c-neg`) scoped to **actual performance only** (NAV Δ, unrealized G/L); the §2.3 non-goal fence holds in the visual layer — **zero value-color on `$ReAlloc`/`%Target`/target captions**, no progress bars / gauges / over-under / variance / target-lines anywhere. Pop comes from a vivid blue accent + a restrained indigo secondary applied to **chrome only** (active nav, hero focal surface, chart line/fill, chips, badges).
- **Typeface = Inter + JetBrains Mono** (chosen over Geist+Geist Mono / Satoshi+IBM Plex for readability); **Hybrid (Type 3)** — Inter for hero NAV + UI, JetBrains Mono for tabular numerics. Self-host at Step 10.
- **Attention hue = Canary-Yellow `#FFEF00`** (chosen over neon-orange `#FFAD00` + true-yellow `#eaea00` via a 3-way live A/B/C). Intensity/contrast-managed (text/border darker for WCAG-AA on white + fill); reserved for staleness/re-auth only; distinct from the negative-performance red + the accent.
- **Dark mode = plan-for** — dark tokens authored now (proven via a Light/Dark toggle), ship light-first, dark fast-follow; ~one token block + a contrast pass, no V1 gate.

### Decision 2 — Canvas: barely-cool, with card elevation (resolving the "lost windows")
The canvas is a **barely-cool near-white** (`--color-neutral-25`, ≈`#fafcfe`) — reads essentially white, cool (not cream/warm). Card surfaces stay **pure white**, so the per-story bordered "window" regions pop again via gentle fill-contrast + a light shadow + their cool border. (A prior over-correction to a literal pure-white canvas had set canvas == surface, flattening the cards; the barely-cool canvas restores the distinction while honoring F/CTO's "cooler white, not cream" intent — the warmth F/CTO had objected to was the attention token + a cached stylesheet, not the canvas.)

### Decision 3 — Two-tier token architecture (the Step-9 taxonomy)
Tokens are structured in two tiers so **no raw hex sits on a semantic token** (every value is discoverable + traceable to a named primitive — closing the recurring "I can't find the token for that value" problem):
- **Tier 1 — primitives (`--color-*`):** named raw values, the only place hexes live (a cool-neutral ramp + blue/indigo/canary/green-red ramps + alpha tokens).
- **Tier 2 — semantic aliases (`--c-*`):** every role aliases a primitive via `var(--color-*)` (e.g. `--c-canvas: var(--color-neutral-25)`, `--c-surface: var(--color-white)`, `--c-attn-solid: var(--color-canary-500)`). The dark theme re-aliases the same semantic names to dark-side primitives — no new hexes in the dark block.

### Decision 4 — Committed home = `docs/DESIGN/` (resolves the [ADR-013](#adr-013) flow-artifact-home follow-up)
A new top-level **`docs/DESIGN/`** artifact (4th alongside `docs/PRD/` / `docs/ARCH/` / `docs/SECURITY/`) is the permanent home for Phase 2 (UX & Design) outputs: the **design system** (`tokens.css` / `screen.css` / `design-system-spec.md` / styled-screen HTML), the **UX flows** (`flows/`), and the **wireframes** (`wireframes/`). NOT folded into PRD (requirements = Phase-1 input) or ARCH (technical architecture = Phase 3) — ARCH **cross-references** `docs/DESIGN/` for the frontend/tokens coupling. Matches the project's HTML-doc + serve-docs/comments convention.

**Consequences.**

- **`docs/DESIGN/` is established + populated** in this PR (the design system + flows + wireframes migrated out of gitignored `temp/`). Working/review-only artifacts (the palette switcher, walkthrough decks, the Phase-2 decisions log) stay in `temp/`.
- **Step 10 (tokens-as-code) remains gated on the Phase-3 frontend-framework choice** (per [ADR-012](#adr-012)). The framework-agnostic token taxonomy (Decision 3) is complete; the framework-specific token export lands at Step 10 once Phase 3 picks the framework. Phase 2 cannot fully close until then — it sits at the ADR-012 framework-coupling pause.
- **Phase 3 ARCH consumes the frontend-framework coupling point + cross-references `docs/DESIGN/`** for the UI/token surface.
- **Follow-up (path-normalization):** the migrated `flows/*.md` + `wireframes/*.md` retain some `temp/phase-2-*` internal cross-references (informational prose) that should be normalized to `docs/DESIGN/`-relative paths in a cleanup pass; the design-system HTML/CSS itself uses clean relative links.
- **Composes with** [ADR-013](#adr-013) (Step-3 flow decisions) + [ADR-012](#adr-012) (parallel execution + framework coupling). Per-decision detail + the full option history live in the gitignored `temp/phase-2-decisions-log.md`.

**Approved by:** F/CTO (2026-05-29 — Step 7 foundation locked via the palette/type/dark/attn checkpoint; design system reviewed + approved at Step 8; two-tier tokens + barely-cool canvas + `docs/DESIGN/` home ratified across the closing review).

---

## ADR-013 — Phase 2 Step 3: UX/design decisions (staleness-marking principle + 6 walk-through decisions)

**Date:** 2026-05-28
**Status:** Accepted
**Phase:** 2 (Step 3 walk-through lock; consolidates the UX/design decisions from the 6-cluster flow drill + 2-sitting F/CTO walk-through; drives Step 4 wireframing + supplies Phase 3 ARCH consumption inputs)

**Context.** Phase 2 (UX & Design) ran in parallel with Phase 3 per [ADR-012](#adr-012). Phase 2 Step 2 drilled all six PRD §2 user-story clusters into flow documents in dependency order (§2.4 cross-cutting → §2.1 net worth → §2.2 asset allocation → §2.3 spending/income → §2.5 estimated taxes → §2.6 monthly report/convergence), each closed via UX draft → PM traceability consult → (Security Reviewer where security-load-bearing) → F/CTO ratification. The drill produced one ratified global principle (D1) mid-stream and surfaced six parked cross-cutting decisions (P1–P6). Step 3 was a full 2-sitting F/CTO walk-through (sitting 1: §2.4/§2.1/§2.2/§2.3; sitting 2: §2.5/§2.6) followed by a one-at-a-time decision pass. The flow documents + per-cluster consult records are working artifacts at `temp/phase-2-flows-*.md` + `temp/phase-2-decisions-log.md` (gitignored per `feedback_working_artifacts_temp_not_docs`); this ADR is the committed, decision-grade consolidation — and the durable bridge for the Phase-3 ARCH handoffs the gitignored logs would otherwise not carry forward.

**Decisions.**

### Decision 1 — D1: staleness-marking surface scope is illustrative, not exhaustive (GLOBAL)
The §2.4.4 non-silent-staleness commitment's enumerated surface list is **illustrative**. Governing rule: **every derived aggregation that consumes stale-account data carries the staleness marker; aggregations are never silently presented as fresh** — including surfaces the §2.4.4 list omits (headline NAV, delta panel, reference dates, `nav-asof-timestamp`, §2.2.3 sub-allocation, §2.3 rollup/drill, §2.5 tax tables, §2.6 report sections). Applies globally; downstream clusters do not re-litigate. Ratified 2026-05-27 (expands a locked commitment's realized surface set → F/CTO ratification). Security Reviewer concurred: strictly-more-conservative, no new attack-surface category.

### Decision 2 — P1: app-level navigation = persistent left sidebar
Always-visible left nav for the ~6 surfaces + Settings. Chosen for the density-first desktop power-user archetype; scales as destinations grow; needs a collapse affordance for narrow viewports. (Over top-tabs / hub-and-spoke drill-down.)

### Decision 3 — P2: Net Worth information hierarchy = number-first, dense single-canvas
Headline NAV + deltas lead → 60-mo trend → composition table, all co-visible on one scrolling canvas; no within-surface sub-tabs (surface-switching is the sidebar's job). (Over trend-first / breakdown-first.)

### Decision 4 — P6: Cash Flow information hierarchy = category×period table (PRD-faithful)
The Income/Expenses × {Month/Q1–Q4/YTD} rollup anchors the surface; per-account drill-down + Historical Expenditures chart secondary. (Over transaction-stream / calendar.)

### Decision 5 — P3: new-symbol classification surfacing = hybrid
The allocation table's `Unsorted` row shows unclassified symbols in-context AND deep-links to a dedicated classification queue for bulk work. (Over queue-only / inline-only.) Consistent with onboarding's New-Symbol-Classification-Queue.

### Decision 6 — P4: re-auth/staleness banner = top chrome bar, conditional, clean-when-healthy
Banner sits in the top chrome (above content, right of the sidebar). **"Persistent" = conditional-persistent:** appears ONLY when a re-auth-required or staleness condition exists; while live it shows on EVERY surface, does not auto-dismiss, and cannot be casually dismissed until the underlying issue resolves. **When healthy → no banner (clean chrome); absence-of-banner = all good.** No always-on health chip (the §2.4 connection-status-chip is not used as an always-present healthy-state indicator; per-account sync status remains available on the Accounts Hub on demand).

### Decision 7 — P5: planning-value editing affordance = settings-UI only (all four)
A dedicated Settings area is the **sole** edit + storage home for all four user-authored planning values: §2.2 allocation `%Target`, §2.3.2 income/expense targets, §2.5.2 tax brackets, §2.6 owner-id header. **No inline editing anywhere** (F/CTO chose pure settings-UI over the best-of-both settings-UI+§2.2-inline option). Supersedes UX's §2.2 inline-cell lean — `alloc-target-edit` routes to Settings. Storage = ADR-005 / Lock-14 settings-store family.

**Consequences.**

- **Step 4 wireframing consumes these directly:** sidebar shell + conditional top-chrome banner + a Settings area housing all 4 planning-value editors (no inline target editing) + single-canvas Net Worth + table-anchored Cash Flow + Unsorted-row→queue deep-link.
- **Phase-3 ARCH handoffs (consolidated here so they survive the gitignored logs):**
  - **A1–A3 (inactive-Plaid lifecycle, from §2.4 PM-1/Sec):** inactive suspends the scheduled-poll for the Item (A1); webhook signature verification (RT-05) + SD-14 state-history recording CONTINUE for inactive Items, only the user-facing surface is suppressed (A2); inactive does NOT delete the SD-03 token (retain per `bounded-Item-active-only`), revoke-on-inactive is NOT V1, V2 un-share = Plaid `/item/remove` + token deletion (A3). Compose with [ADR-011](#adr-011) Decision 8 + Decision 1 (§6 privileged-context-write).
  - **A4 (wash-sale, from §2.5 PM-2):** the §2.4.3 sell-transaction gains a user-marked wash-sale flag + user-entered disallowed-loss field; the Lock-10 immutability mechanism (mutable-annotation vs reverse-and-replace) is Architect/Sec's call under [ADR-011](#adr-011) Appendix-B flag (j); validation: disallowed-loss ≤ realized loss on the transaction + tenant-scoped.
  - **H1 (planning-value write-path):** all four P5 surfaces inherit the Lock-14 settings-store fence (Zod `.strict()` mass-assignment + numeric adversarial battery + tenant-scoping); the §2.2 `%Target` write is a per-Sub-Cat **keyed array** → the Sub-Cat key must be validated against the seeded taxonomy (no forged/cross-tenant key); §2.5.2 brackets are multi-row keyed.
  - **H2 (as-of-date):** §2.3.3 (client-toggle) + §2.6 (server-derived) reuse one Lock-15 mechanism; tenant-isolation independent of the date filter; RT-25.
  - **`nav-asof-timestamp` (Lock-8-derived):** Architect confirms `pfin.nav` exposes a usable last-current-NAV-computation timestamp + sets the stale-materialization warning threshold.
  - **RT-13 tracks D1:** widening the staleness surface set widens RT-13's verification scope — every newly-realized staleness surface inherits the requesting-tenant-scoped credential-state-resolution requirement (Phase-3 + Phase-6 PR-review fence).
  - **§2.6 injection invariants:** INV-1 — plain-text-only commentary/owner-id is security-load-bearing (the V2+ markdown path is a security-surface expansion requiring a Sec re-touch, NOT a harmless refinement); INV-2 — output-encoding must span HTML view + PDF export and couples to Appendix-B flag (a) (PDF render-path open). RT-11 (commentary) + RT-12 (owner-id) land at the mandatory §4 Sec authoring.
  - **Seed-content recommendation:** the cash-flow taxonomy seed should include a catch-all "Uncategorized" Sub-Cat (→ [ADR-004](#adr-004) / Architect Phase-3 bootstrap) so every transaction always sits in a visible bucket (keeps the §2.3 "no review queue" decision robust).
- **Follow-up — Phase 2 flow-artifact committed home:** the six flow documents remain in gitignored `temp/`; their committed home (e.g., a `docs/UX/` artifact) is an open decision, naturally resolved when wireframes + design system land. Tracked, not blocking.
- **No supersession.** Composes with [ADR-011](#adr-011) (Phase-3 input surface) + [ADR-012](#adr-012) (parallel execution). Per-cluster bullet-level detail lives in the gitignored `temp/phase-2-*` working files.

**Approved by:** F/CTO (2026-05-28, via the Step 3 walk-through: 2-sitting flow review signed off + P1–P6 decided one-at-a-time; D1 ratified 2026-05-27 during the drill).

---

## ADR-012 — Parallel Phase 2 (UX & Design) + Phase 3 (Technical Architecture) execution

**Date:** 2026-05-27
**Status:** Accepted
**Phase:** Phase 1 → Phase 2 + Phase 3 transition (R-outer-frame sequencing under [ADR-009](#adr-009) Decision 2)

**Context.** Phase 1 (Product Definition) closed 2026-05-26 with all 16 substantive architectural locks ratified + candidate P3 disposed + Lock 9 amended (per [ADR-011](#adr-011)). The R/P/I+V outer frame per ADR-009 Decision 2 places mosko's Phases 1 + 2 under the template's "Research" outer category; Phase 3 (Technical Architecture) opens the "Plan" outer category. At phase-transition invocation, three sequencing options for Phase 2 vs Phase 3 were available: (1) Sequential R-strict — fully close Phase 2 before opening Phase 3; (2) Defer-Phase-2 — open Phase 3 immediately, Phase 2 lands post-ARCH or alongside Phase 4; (3) Parallel execution — open both phases concurrently with explicit coordination at coupling touchpoints.

PRD §2 already locks 32 V1 user stories at decision-grade clarity, so Phase 3 has a complete requirements surface independent of Phase 2 flows. ADR-011 + the 13 Phase 3 carry-over tasks give Architect a fully-loaded immediate work surface. Phase 2 deliverables (flows + wireframes + design system + tokens) have no upstream blockers either — PRD §2 is their input. The only hard coupling point between the two phases is frontend framework choice (Phase 3 Architect deliverable) ↔ design tokens format (Phase 2 Visual Designer deliverable); both can begin work independently and converge at the framework-choice gate.

**Decision.** Open Phase 2 and Phase 3 concurrently per option 3 (parallel execution). Architect leads Phase 3 ARCH drafting from PRD §2 + ADR-011 + locks log + 13 carry-overs; UX Designer + Visual Designer lead Phase 2 flows → wireframes → design system → tokens from PRD §2. Both phases work in separate team contexts (`phase-3-arch-drafting` + `phase-2-ux-design`, created at their respective work openings); coordination touchpoints are explicit at the framework-choice ↔ design-tokens-format coupling. Both phases close together at the Phase 4 (Project Scoping) entry gate — Phase 4 consumes both ARCH HTML and the design-system spec. If one phase finishes before the other, the further-along phase marks ✅ Complete in its own section but the WORKFLOW.md header pointer remains at "Phase 2 + Phase 3 (parallel)" until both close.

**Why.** PRD §2 + ADR-011 already provide both phases with fully-specified inputs; serializing them adds calendar without unlocking new information. The chain-attack-catch density observed in Phase 1 Step 4 (Sec found 8 catches Architect missed at joint reviews — see [ADR-011](#adr-011)) suggests Phase 3 will benefit from F/CTO bandwidth focused on architectural decisions; parallelizing Phase 2 reduces idle-Phase-2-roster cost without diluting that bandwidth (Phase 2 lead agents — UX + Visual Designer — don't compete with Architect or Sec for F/CTO review cycles). The decision-by-Phase-4 gate provides a natural convergence point.

**Alternatives considered.**

- **Sequential R-strict (option 1).** Rejected — tightest R-outer-frame discipline but trades calendar for no information gain; Phase 3 inputs are already complete at PRD §2 + ADR-011. The R-outer-frame discipline per ADR-009 Decision 2 is a grouping convention, not a hard sequencing constraint — phases within the same outer category can overlap when their input surfaces are independent.
- **Defer-Phase-2 (option 2).** Rejected — defers a planning artifact without surfacing a forcing function. Phase 2 deliverables eventually need to land before Phase 5 (Workshop Setup) regardless; deferring creates a downstream cliff rather than spreading the work. Visual Designer's "mandatory palette + typography F/CTO checkpoint" gate also benefits from early scheduling.

**Coordination expectations.**

- **Coupling touchpoint:** Architect's frontend framework choice (Phase 3) ↔ Visual Designer's design tokens format (Phase 2). Visual locks the abstract tokens taxonomy (framework-agnostic) without Architect input; tokens-as-code finalization waits on the framework-choice gate, with a framework-agnostic intermediate-format fallback (Style Dictionary / W3C design-tokens JSON) available at F/CTO's call if Phase 3 slips substantially.
- **Team-mode coordination:** Phase 2 + Phase 3 create separate teams (`phase-2-ux-design` + `phase-3-arch-drafting`) per [ADR-003](#adr-003); team-lead (main session) bridges them. Cross-team coordination at the coupling touchpoint routes through team-lead, not direct peer-to-peer (per the Step 4 synthetic-team routing-discipline lesson — see ADR-011 Decisions 1-4 Consequences + WORKFLOW.md Phase 1 Step 4 lessons-learned).
- **Decision-by-Phase-4 gate:** both phases close before Phase 4 (Project Scoping) opens. If one phase lags, Phase 4 waits. No partial-Phase-4 entry under one-phase-only closure.
- **Pointer convention:** WORKFLOW.md header current-phase pointer stays at "Phase 2 + Phase 3 (parallel)" until both phases close. Individual phase sections advance their own Status independently.
- **Sec re-consult discipline:** Phase 3 architectural surfaces inherit the Step 4 Sec joint-review pattern (chain-attack-catch density warrants mandatory Sec re-consult at every surface lock per [ADR-011](#adr-011) Decision 4 §10 defense-in-depth fencing). Phase 2 does not require Sec re-consult (no security-load-bearing surface in flows / wireframes / tokens).

**Cross-references.**

- WORKFLOW.md §"Phase 2 — UX & Design" + §"Phase 3 — Technical Architecture" — both phase sections receive Detailed-steps subsections at this phase-transition PR (drafted by UX + Visual Designer teammates + Architect teammate in team `phase-2-3-entry` on 2026-05-27).
- [ADR-009](#adr-009) Decision 1 (team-lead as main session) + Decision 2 (R/P/I+V outer frame).
- [ADR-011](#adr-011) — Phase 3 input surface (16 locks + 4 meta-patterns + 13 carry-overs).
- [ADR-003](#adr-003) — team-mode coordination conventions inherited by Phase 2 + Phase 3 team setup.
- `docs/handoff-prompts.md` § Phase-transition prompt — invoked to produce this ADR + WORKFLOW.md updates + MILESTONES update.

**Approved by:** F/CTO (2026-05-27, via phase-transition sequencing chooser at session start; locked option 3 "Run Phase 2 and Phase 3 in parallel" against options "Defer Phase 2; invoke Phase 3 now" and "Fast-track Phase 2 first (sequential)". 9 substantive flags from teammate drafts ratified at-recommend across the walk-through.).

---

## ADR-011 — Phase 1 Step 4 architectural drilling: 16 lock decisions + 4 project-convention meta-patterns

**Date:** 2026-05-26
**Status:** Accepted
**Phase:** 1 (Step 4 lock; consolidates 16 architectural decisions + 4 cross-cutting project-convention meta-patterns ratified during the active drilling cycle 2026-05-25 → 2026-05-26; lands the canonical-reference layer for Phase 3 implementation work; Phase 3 entry gate)

**Context.** Phase 1 Step 4 (Architectural overview consult; Architect lead; Phase 3 entry gate per [ADR-009](#adr-009) Decision 2) executed an active drilling cycle against the 16 substantive architectural flags + 3 candidate-P flags surfaced at Pass 1 framing (`temp/step-4-arch-overview-pass-1.md`). Per Architect's wave sequencing, the 16 flags drilled across 5 waves: Wave 1 (Flag #1 RLS baseline + alphanumeric track P1/P2/E1a/E2 + Flag #3 taxonomy + Wave 1 step 2 Flag #10/#12 NAV+CPI); Wave 2 (Flag #4 reconciliation + Flag #5 manual-entry); Wave 3 (Flag #6 snapshot store + Flag #7 snapshot-vs-live render); Wave 4 (Flag #8 workers + Flag #9 settings + Flag #13 as-of-date); Wave 5 (Flag #11 cost feasibility — synthesis drill last). Each lock followed the project pattern: Architect drills A/B/C options + lean; Sec joint review on architecturally Sec-load-bearing surfaces; F/CTO ratifies with mods. The cycle produced 16 locks closed + candidate P3 (FMP/stock-screening incumbent-exceeds-V1) resolved as V1-default + Lock 9 amended at Lock 15 (re-introduces `account_trans.created_at` as IMMUTABLE post-INSERT).

Drilling output: 16 lock entries totaling ~1200 lines of locked architectural commitment with full Sec-mod inventory at the authoritative state file `temp/step-4-locks-log.md` (gitignored per `feedback_working_artifacts_temp_not_docs`). Sec found 23+ V1-ship-blockers across reviews including 4 instances of the cross-tenant FK-bypass attack family + 8 distinct chain-attack catches that Architect's drills missed but Sec's joint-review surfaced. 13 Phase 3 carry-over tasks booked in team task tracker `phase-1-step-4` (Tasks #11/#13/#15/#16/#17/#20/#26/#29/#32/#33/#34/#35/#36) with full per-lock Sec-mod implementation descriptions. 8 locks-log meta-patterns identified across the drilling cycle — 4 emerged as project-convention candidates ratified at Step 4 close per Decisions 1-4 below.

This ADR establishes the canonical-reference layer for the 16 locks at the consolidation scale appropriate for Phase 3 consumption — bullet-level per-lock content elaborates at the locks log; ADR-011 captures the decision shape, rationale, and cross-flag implications at the granularity Phase 3 ARCH drafting (Phase 3) + Phase 5 migration design + Phase 6 PR review will consume. Bullet-level commitments at PRD/SECURITY HTML artifacts remain mutable through future revisions if the canonical references hold steady; new architectural commitments require ADR-011 amendment or supersession.

**Decisions.**

### Decision 1 — Privileged-context-write discipline for non-JWT writes (project-convention meta-pattern §6)

For all non-JWT writes (webhook handlers + cron workers + scheduled-poll workers + future privileged contexts), V1 commits to a four-clause discipline ratified across Locks 4 + 7 + 11 + 13:

- **(a)** Ingress under no JWT (writer is not a user session).
- **(b)** Writes execute under `service_role` (bypasses RLS by design at the DB layer).
- **(c)** Tenant correctness derives from code, not RLS (RLS can't help when there's no JWT; explicit `users_id` binding at the entry boundary).
- **(d)** Explicit audit log captures the tenant-resolution chain (forensic-detectability when the code's tenant-decision goes wrong).

**Origin:** Lock 4 mod #6 (Plaid webhook handler). **Confirmed reusability:** Lock 7 NAV worker; Lock 11 monthly_report cron mod #2; Lock 13 `pfin_back_etl` worker architecture (concretized as `TenantBoundConnection` class + same-transaction audit-log per Lock 13 mods #3 + #4). **Forward applicability:** Lock 9 dedup writes (Plaid sync path); any V2+ privileged-context-write surface emerging.

**Why ADR-able:** four consecutive locks surfaced the same discipline; expected to recur at every future privileged-context surface. Names the pattern so future surfaces can be evaluated against it without rediscovering. New V1 or V2 privileged-context surface MUST adopt the four-clause discipline at design time.

**Cross-references:** Locks 4 / 7 / 11 / 13. `temp/step-4-locks-log.md` §6 meta-pattern. Sec confirmed reusability at every joint flag review.

### Decision 2 — Immutable + INSERT-new-version discipline for audit-class surfaces (project-convention meta-pattern §7)

For all audit-class surfaces (financial-correctness data + compliance-attestation-bearing tables), V1 commits to immutable rows at the policy/trigger layer + INSERT-new-version regeneration where corrections are required. Pattern ratified across Locks 9 + 10 + 11:

- Rows are append-only at the RLS policy + DB-trigger layer (UPDATE/DELETE blocked across both `authenticated` AND `service_role` roles).
- "Updates" become NEW rows with explicit relationship to predecessor (FK or status ENUM).
- Audit trail is the table itself; no separate audit table needed.
- Composes with §6 privileged-context-write discipline — service_role contexts still can't UPDATE due to DB-trigger layer.

**Surfaces ratified:**
- **Lock 9 (reconciliation_event + reconciliation_event_trans):** append-only RLS; tamper-proof audit trail.
- **Lock 10 (account_trans):** immutable rows; edits via reverse-and-replace INSERT (`is_reverse BOOLEAN` + `replaces_trans_id` FK).
- **Lock 11 (monthly_report):** immutable per row; regeneration via INSERT-new-version with `generation_status` ENUM (draft → final → superseded); partial UNIQUE on `(users_id, target_month) WHERE generation_status = 'final'`.

**Why ADR-able:** §SECURITY §4.6 audit-log retention commitment held by-construction (no UPDATE means no audit gap); money-correctness failure modes (silent drift, silent cascade-skip) eliminated by immutability; cross-tenant chain attacks (Decision 3 below) close cleanly via matched-account WITH CHECK + immutability of the chain.

**Cross-references:** Locks 9 / 10 / 11. `temp/step-4-locks-log.md` §7 meta-pattern. Lock 12 Decision 16 below strengthens to fence tenant anchor (`users_id`) + audit-load-bearing columns (`target_month`, `account_id`), not merely value columns.

### Decision 3 — Cross-tenant FK-bypass attack family + matched-tenant validation (project-convention meta-pattern §8)

Any FK-shaped reference column (single FK, self-FK, INTEGER[] array element) that crosses an isolation boundary requires **explicit matched-tenant validation** — DB-level WITH CHECK constraint (single columns) or BEFORE INSERT/UPDATE trigger (array elements PostgreSQL can't express declaratively). PostgreSQL FK constraints are silent on RLS: the constraint validates the referenced row exists; it does NOT validate the referenced row is within the referring user's isolation scope. Without explicit matched-tenant validation, FK-shaped columns create chain-attack surfaces that defeat RLS protection at the schema layer.

**Four V1 instances locked:**
- **Lock 9 mod #1:** `pfin.reconciliation_event_trans (event_id, account_trans_id)` — WITH CHECK matching `reconciliation_event.account_id` to `account_trans.account_id`.
- **Lock 10 mod #2:** `pfin.account_trans.replaces_trans_id` self-FK — WITH CHECK matching target's `account_id` to row's `account_id`.
- **Lock 11 mod #9:** `pfin.monthly_report.included_reconciliation_event_ids INTEGER[]` — BEFORE INSERT/UPDATE trigger validating every array element's `reconciliation_event.users_id` equals row's `users_id`.
- **Lock 12 Architect-spec + mod #2:** `pfin.monthly_report_account_snapshot.account_id` — matched-tenant validation trigger + parent immutability extension fencing `monthly_report.users_id` UPDATE post-creation.

**Why ADR-able:** four consecutive flags surfaced the pattern; default-discipline lowers the cognitive load on Sec reviews (forces explicit consideration at design time rather than catching ad-hoc per surface). Composes with §6 + §7 + §10 to form a defensive layer on top of RLS. Any new V1 or V2 surface introducing a FK-shaped reference column (including INTEGER[] arrays) MUST include matched-tenant validation in its DDL.

**Cross-references:** Locks 9 / 10 / 11 / 12. `temp/step-4-locks-log.md` §8 meta-pattern. Decision 16 below (Lock 12) strengthens the family with tenant-anchor-immutability extension. Decision 19 below (Lock 15 / Flag #13) confirms NOT a new instance at V1 (settings-table writes are user-session-bounded; FK-bypass becomes live only at V2+ live-tax-API ingestion under service_role).

### Decision 4 — Defense-in-depth fencing across surface boundaries + schema-level orthogonality awareness (project-convention meta-pattern §10)

V1 commits to defense-in-depth fencing for security-load-bearing surfaces — fence at MULTIPLE layers simultaneously rather than at any single layer. Three classes of surface accumulated across Locks 13 + 14 + 15:

- **Privileged-context surfaces (Lock 13):** fence at code (`TenantBoundConnection` class + CI grep fence) + CI (no raw `psycopg2.connect()` outside the class) + JWT shape (authenticated-tier-only; dedicated signing key; nonce replay protection) + **infrastructure-credential-presence** (no `SUPABASE_*` env vars in PDF worker container; no Postgres client installed in Dockerfile — preserves Lock 12 mod #1 read-path-only fence by-construction against future-optimization regressions).
- **User-facing direct DB write surfaces (Lock 14):** fence at app-layer (Zod `.strict()` schema validation + mass-assignment prevention; `users_id` from `auth.uid()` not `req.body`) + numeric-input adversarial battery (NaN/Inf/currency-string regex/overflow/scientific-notation/locale-formatted reject) + RLS WITH CHECK at DB layer + DB-trigger backstops (monotonicity; `updated_at` UPDATE-refresh).
- **Schema-level orthogonality awareness (Lock 15 catch on Lock 9):** drop-column corrections MUST be evaluated against ALL downstream PRD commitments, not just the immediate-driver concern. Lock 9 correction #3 dropped `account_trans.created_at` for event-date immutability — orthogonal to row-insertion-time semantics needed by Lock 15 / Flag #13 §2.3.3 retroactive-edit-historical-view commitment.

**Why ADR-able:** the same chain-attack pattern (catching multiple-layer failures) keeps surfacing. Sec found 8 chain-attack catches across the drilling cycle that Architect's drills missed — defense-in-depth is the discipline that makes catches possible at design time rather than at attack time. Composes with §6 (privileged-context-write) + §7 (immutable INSERT-new-version) + §8 (cross-tenant FK-bypass).

**Cross-references:** Locks 13 / 14 / 15. `temp/step-4-locks-log.md` §10 candidate meta-pattern (further-strengthened at Lock 15 schema-level orthogonality). Sec re-pings at every Phase 3 / Phase 6 multi-layer-surface review verify the discipline holds.

### Decision 5 — Lock 1 / Flag #1: Multi-tenant + RLS Option A (Supabase Auth + native RLS)

**Locked option:** Option A — Supabase Auth + native RLS as V1 baseline + selective Option C overlay deferred to Phase 3 detail design on RT-02 (Plaid Items table) + RT-05 (webhook handler) critical-severity surfaces. **Rationale:** Option A satisfies every PRD/SECURITY lock at zero incumbent-switching cost; Option B portability benefits not load-bearing for single-tenant V1 invite-only-V2 trajectory; selective C-on-A captures financial-correctness blast-radius wins on critical-severity RT surfaces without universal-wrapper maintenance tax.

**Cross-references:** locks-log Lock 1; PRD §1.4 + §7.3; SECURITY §4.1 axis (i); ADR-008 Decision 1 axis (i) baseline; sets foundational RLS stance under which all downstream locks land.

### Decision 6 — Lock 2 / Flag P2: account_users V1-dormant; preserve as-built schema

**Locked option:** Option A — document `account_users` table + `fn_grant_creator_access` trigger + `rd_access`/`wr_access` flags as V1-dormant. PRD §7.3 adds additive bullet acknowledging the dormant per-account ACL primitive. V1 UI does not expose sharing or invitation flows. V2 invite-only expansion enables the UI surface against this scaffolding without a data migration. F/CTO-added guardrail: `feedback_incumbent_exceeds_v1_review` memory established (when incumbent code/schema exceeds V1 PRD commitment, promote to a P-flag with options + ADR; do NOT auto-accept via selective adoption).

**Cross-references:** locks-log Lock 2; PRD §7.3; ADR-008 Decision 1 Axis (i); composes with Lock 3 E1a-B RLS-shape decision. Memory `feedback_incumbent_exceeds_v1_review`.

### Decision 7 — Lock 3 / Flag E1a: account_trans RLS shape (Option B — account_users.rd_access-JOIN)

**Locked option:** Option B — `account_users.rd_access`-JOIN at SELECT; `wr_access` at INSERT/UPDATE/DELETE WITH CHECK. F/CTO override of Architect's Option A lean (created_by-direct) — exercises multi-user RLS infrastructure at V1 so V2 sharing-UI lands against an RLS pattern already in production. Sec blessed with 3 V1-SHIP-BLOCK mods + 1 advisory: (1) tighten `account_users` UPDATE policy via column-level `REVOKE UPDATE; GRANT UPDATE (nickname, notes)` mirroring `user_profile` pattern (without it, tenant A can re-tenant their `account_users` row to tenant B — full cross-tenant R/W leak); (2) elevate `fn_grant_creator_access()` to `SECURITY DEFINER` + verify it fires under V1 RLS; (3) write-path WITH CHECK uses `wr_access`, not `rd_access`; (4) advisory SECURITY annotation noting V1 exercises V2 sharing-shape ACL.

**Cross-references:** locks-log Lock 3; Task #11 Phase 3 carry-over (E1a Sec mods + E1b NULL bug). Sec's load-bearing catch: `account_users` UPDATE-policy cross-tenant-pivot bug — latent under Option A; active under Option B — would have shipped silently.

### Decision 8 — Lock 4 / Flag #2: Plaid integration (Option C — pragmatic hybrid)

**Locked option:** Option C — Supabase Vault/pgsodium column-level encryption on `plaid_items.access_token_encrypted` BYTEA + denormalized token storage + Express/Next webhook signature verification via Plaid SDK HMAC + dedup hybrid (partial-unique-index `(account_id, plaid_transaction_id)` + existing `(account_id, import_hash)`) + append-only `plaid_item_state_history` table (V1 audit-retention commitment per §4.6 requires it). **Sec's 6 mods** (3 V1-SHIP-BLOCK + 3 advisory): (1) pgsodium decrypt-view permission scoped to service_role only + Vault key-management Phase 3 lock; (2) webhook handler explicit `users_id`-binding from `plaid_items.users_id` lookup at the Plaid Item ID; (3) webhook idempotency via `plaid_webhook_id` UNIQUE; (4) ItemUpdate event-state classification mapped to 4-class credential-error enum per §2.4.4; (5) §SECURITY §4.2 webhook-bypass-risk annotation; (6) **privileged-context-write discipline established** (§6 meta-pattern origin). E1a-B dependency: Plaid Items table inherits `account_users.rd_access`-JOIN shape.

**Cross-references:** locks-log Lock 4; Task #13 Phase 3 carry-over (Plaid Sec mods). Sec's load-bearing catch: pgsodium-default-decrypt-view permission gap — would have defeated RT-02 (Plaid Item table RLS critical-severity test) entirely.

### Decision 9 — Lock 5 / Flag E2: acct_number storage class

**Locked option:** Option B — Preserve as-built `acct_number` column on `pfin.account` with masked-rendering convention (4-char suffix display only; full value never user-facing). SD-15 entry NEW (medium tier; tenant-scoped; indefinite). Sec mods (3 advisory): (1) Phase 3 ARCH masked-rendering helper implementation; (2) Phase 6 PR-review fence on full-value disclosure surfaces; (3) §SECURITY §4.6 PCI-DSS scope posture sub-section (V1 not PCI-DSS-scope since `acct_number` is masked-only; V2+ unmasking surface triggers PCI consult).

**Cross-references:** locks-log Lock 5; Task #15 Phase 3 carry-over (E2 Sec mods). New SD-15 entry per §SECURITY §4.4 expansion.

### Decision 10 — Lock 6 / Flag P1: users_id schema rename

**Locked option:** Sweep `tenant_id` → `users_id` across all V1 user-data tables. PRD §1.4 + §7.3 + SECURITY §4.1 axes (i)–(iv) + §4.4 SD matrix + ADR-008 Decision 1 axis (i) ratify the new name. F/CTO-driven rename for V1 single-user-V1 + multi-tenant-from-day-one shape clarity (the column anchors to `auth.users(id)` — `users_id` is the literal semantic; `tenant_id` was a generic shape that implied a tenant table that V1 doesn't have). Phase 3 implementation does the actual DDL rename; PRD/SECURITY/ADR text updates align in Step 4 close PR.

**Cross-references:** locks-log Lock 6; Task #16 Phase 3 carry-over (P1 schema rename + PRD/Sec adoption). Affects all V1 RLS predicates per axis (i).

### Decision 11 — Lock 7 / Flag #3: taxonomy migration (Option A — V1 user_taxonomy with seed-only V1)

**Locked option:** Option A — single `pfin.user_taxonomy` table (per-user user-editable taxonomy); V1 seed-only (no UI for taxonomy CRUD); V2+ taxonomy-CRUD-UI as expansion. Two-level Cat × Sub-Cat for asset (§2.2.1) + cash-flow (§2.3.1) + `tax_relevant` boolean + `tax_character` enum per ADR-006 Axis 2. V1 bootstrap seeds from F/CTO's existing-system taxonomy. Sec posture: user-scoped RLS standard; no novel surface. Architect Phase 3 picks the precise DDL shape (single table vs split asset/cashflow tables — Phase 3 decision per App B §2.2 (a) + §2.3 (a)).

**Cross-references:** locks-log Lock 7; Task #17 Phase 3 carry-over (taxonomy migration Option A). Per ADR-006 + ADR-004 Decision C.

### Decision 12 — Lock 8 / Wave 1 step 2 / Flag #10 + #12: NAV + CPI ingestion

**Locked option:** Combined drill — NAV materialized per-month rows in `pfin.nav` (worker computes month-end; Lock 11 monthly_report reads as O(1) lookup) + CPI-U historical import via `pfin_back_etl` (incumbent BLS API integration; back to Dec-2015 NAV anchor per PRD §2.1.3). NAV worker established §6 privileged-context-write discipline reusability (confirmed Lock 4's Plaid webhook pattern extends cleanly to cron workers). Sec mods (2 advisory): (1) NAV materialization tenant-binding follows Lock 4 mod #6 pattern; (2) CPI ingestion is read-only public-data; no new SECURITY surface.

**Cross-references:** locks-log Lock 8; Task #20 Phase 3 carry-over (Wave 1 step 2 Sec mods). `reference_pfin_back_etl` memory.

### Decision 13 — Lock 9 / Flag #4: dedup + reconciliation (Addendum 2 + Lock 9-A amendment per Lock 15)

**Locked option:** Per-transaction explicit reconciliation via `pfin.reconciliation_event_trans` join table (replaces date-range derivation); statement-blessed values on `reconciliation_event` (`statement_balance` + `statement_quantity`); multi-dimension reconciliation support (single trans linked to multiple events); NAV via `eod_price` lookup at read time (no stored NAV column); naming sweep drops `_cents` suffix; trigger logic fix on `holdings_checkpoint`; drop denormalized flags (`is_plug` BOOLEAN — Sub-Cat is discriminator; `mode VARCHAR(4)` — not load-bearing). **F/CTO correction #3 dropped `account_trans.created_at`** (per-transaction model handles retroactive inserts by construction) — **AMENDED at Lock 9-A per Lock 15 (Decision 19 below)**: correction #3 was scope-narrow (addressed event-date immutability); did NOT anticipate §2.3.3 retroactive-edit-historical-view use case. **Lock 15 mod #1 V1-SHIP-BLOCK re-introduces `account_trans.created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` IMMUTABLE post-INSERT** (inherits Lock 10 mod #8 trigger pattern). **Sec's 6 mods + 1 advisory + 1 hardening + 1 forward-fence** including V1-SHIP-BLOCK on append-only RLS + matched-account WITH CHECK (Decision 3 above first instance); cost-basis cascade concurrency control via `SELECT ... FOR UPDATE` row-lock; SD-matrix expansion 14→19 (SD-16 reconciliation_event HIGH + SD-17 holdings_checkpoint medium + SD-18 reconciliation_event_trans low); RT-16 + RT-17 HIGH; §4.6 four-surface audit-family annotation. **ADR-008 amendment required** at Step 4 close documenting Lock 9 correction #3 partial-reversal rationale + SD-00 row light addendum for re-introduced `created_at`.

**Cross-references:** locks-log Lock 9 + Lock 15; Task #26 Phase 3 carry-over (Flag #4 Sec mods + per-transaction reconciliation model). Sec's load-bearing catch: cross-tenant link attack via `reconciliation_event_trans` (FK enforcement silent on RLS).

### Decision 14 — Lock 10 / Flag #5: account_trans immutable + reverse-and-replace

**Locked option:** `account_trans` rows immutable post-INSERT; edits via reverse-and-replace pattern (`is_reverse BOOLEAN` + `replaces_trans_id` FK self-reference; matched-account WITH CHECK per Decision 3). RLS-default-deny on UPDATE + DB-trigger blocking UPDATE across both `authenticated` AND `service_role` (Lock 10 mod #8 pattern — referenced by Lock 14 mod #9 trigger reuse + Lock 15 mod #1 trigger extension). Sec's 10 mods including SD-00 immutability addendum + RT-18 immutability invariant suite + cross-flag chain-attack catch on `replaces_trans_id` self-FK (Decision 3 second instance). §7 immutable + INSERT-new-version discipline ratified at this lock (Decision 2 above).

**Cross-references:** locks-log Lock 10; Task #29 Phase 3 carry-over (immutable account_trans + 10 Sec mods + RT-18). Sec's load-bearing catch: `replaces_trans_id` self-FK cross-account replacement attack.

### Decision 15 — Lock 11 / Flag #6: monthly_report snapshot store (Option B — minimal + read-time composition)

**Locked option:** Option B — minimal report-identity table (`monthly_report` with `included_reconciliation_event_ids INTEGER[]` + `generation_status` ENUM draft/final/superseded) + composition at read time (joins `holdings_checkpoint` + `eod_price` + `account_trans` + `tax_character` + `pfin.nav` at render); immutable + INSERT-new-version regeneration with partial UNIQUE `(users_id, target_month) WHERE generation_status = 'final'`. **Sec's 9 mods** (3 V1-SHIP-BLOCK + 6 advisory) including: V1-SHIP-BLOCK SECURITY INVOKER on read-time composition (no DEFINER bypass); V1-SHIP-BLOCK cron tenant-binding discipline (§6 meta-pattern instance per Decision 1); V1-SHIP-BLOCK immutable INSERT-new-version regeneration (Decision 2 instance — hard-overwrite UPDATE would lose `included_reconciliation_event_ids` + `owner_header_at_generation` history); SD-12 row revision (HIGH; reference IDs + user-input; financial values composed at read time); RT-19 read-time composition tenant-scoping; **mod #9 V1-SHIP-BLOCK `INTEGER[]` matched-tenant trigger** (Decision 3 third instance — INTEGER[] columns can't carry FK constraints on array elements; cross-tenant `reconciliation_event_id` population is real audit-trail-integrity leak).

**Cross-references:** locks-log Lock 11; Task #32 Phase 3 carry-over (monthly_report + 9 Sec mods + RT-19). Sec's load-bearing catch + project-convention consolidation: §7 immutable + INSERT-new-version discipline explicitly named at this lock; INTEGER[] matched-tenant trigger pattern as Decision 3 third instance.

### Decision 16 — Lock 12 / Flag #7: snapshot-vs-live render-path composition (Option A — sibling child table)

**Locked option:** Option A — sibling per-account snapshot child table `pfin.monthly_report_account_snapshot (monthly_report_id, account_id, acct_name_at_generation)` + matched-tenant validation trigger on `account_id` (Decision 3 fourth instance); RLS via parent FK chain; single SECURITY INVOKER composition helper called from all three entry paths (in-app render + PDF export + historical-month view); live-staleness join reads `plaid_items.state` direct (NOT `plaid_item_state_history`); β′ resolution from v1.30 verify-pass binds banner stale-account-name strings to requesting tenant's snapshot only. **Sec's 8 mods** (3 V1-SHIP-BLOCK + 5 advisory) including: V1-SHIP-BLOCK SECURITY INVOKER read-path-only fence on composition helper; V1-SHIP-BLOCK **immutability trigger extended to fence parent `users_id` + `target_month` UPDATE on monthly_report** (chain-attack via parent re-tenant orphaning child snapshot rows from original tenant — Sec's 5th chain-attack catch); V1-SHIP-BLOCK service_role bypass DB-trigger on child table; ON DELETE RESTRICT (not CASCADE); SD-12 child sub-class addendum; RT-13 amendment (SECURITY INVOKER read-path-only fence verification); new RT-20 HIGH (fourth-instance FK-bypass + service_role bypass + parent immutability extension).

**Cross-references:** locks-log Lock 12; Task #33 Phase 3 carry-over (child table + 8 Sec mods + RT-20 + RT-13 amendment). Sec's load-bearing catch: immutability trigger MUST fence the tenant anchor itself (`users_id`) + audit-load-bearing columns (`target_month`, `account_id`), not merely value columns — strengthens Decision 2 (§7) and Decision 3 (§8) jointly.

### Decision 17 — Lock 13 / Flag #8: background-worker architecture (Option C — hybrid)

**Locked option:** Option C — hybrid worker location: `pfin_back_etl` (Python on Coolify; incumbent extended) hosts monthly-report cron + Plaid scheduled-poll + NAV + BLS + FMP; V1 app retains Plaid webhook handler + in-app render path; NEW Node PDF worker container (Puppeteer browser-context-per-render hitting V1 app render URL with short-lived signed JWT under user-session identity). Lock 12 mod #1 read-path-only fence preserved by-construction (HTTP-via-V1-app) + by-infrastructure (Sec mod #2 — no Supabase credentials in PDF worker container). **Sec's 10 mods** (4 V1-SHIP-BLOCK + 6 advisory) including: V1-SHIP-BLOCK PDF worker JWT shape (authenticated-tier-only; dedicated signing key; 60s freshness; nonce replay); V1-SHIP-BLOCK PDF worker no-direct-DB-access infrastructure fence (no `SUPABASE_*` env vars; no Postgres client installed; **§10 meta-pattern instance per Decision 4 — infrastructure-credential-presence layer**); V1-SHIP-BLOCK `TenantBoundConnection`-only CI fence (compile-time complement to runtime SQL-log assertion); V1-SHIP-BLOCK same-transaction audit-log discipline (`emit_audit_log()` on same `conn` in same SERIALIZABLE tx); Puppeteer browser-context-per-render hardening (system-fonts-only fence + Chromium flags `--disable-features=BackgroundFetch,ServiceWorker,BackgroundSync` + cache-disable + per-render PDF metadata clear); **mod #8 cross-language audit-log schema-as-contract** via new `pfin.plaid_sync_audit` table with `source` ENUM discriminator; RT-21 HIGH (PDF worker JWT verification) + RT-22 medium (PDF worker container credential audit); RT-09 + RT-10 amendments. §6 privileged-context-write discipline concretized as `TenantBoundConnection` class.

**Cross-references:** locks-log Lock 13; Task #34 Phase 3 carry-over (`pfin_back_etl` extension + V1 app `/internal/pdf-render` endpoint + Node PDF worker + 10 Sec mods). Sec's load-bearing catch: infrastructure-credential-absence as defense-in-depth layer (future-regression-fence) — §10 meta-pattern (Decision 4) first formal instance. `reference_pfin_back_etl` + `reference_hetzner_cax21` memories.

### Decision 18 — Lock 14 / Flag #9: settings store (Option B — per-domain tables fully split)

**Locked option:** Option B — four per-domain tables (`pfin.planning_target` + `pfin.tax_bracket_schedule` + `pfin.tax_bracket_row` + `pfin.owner_identification`); greenfield (no incumbent settings tables in `pfin_dash`); UPSERT-in-place + `updated_at`; no edit-history rows (settings NOT audit-class); `tax_year SMALLINT` from V1 day-one for forward-compat-additive multi-year history (V1 reads `EXTRACT(YEAR FROM CURRENT_DATE)` for §2.5.3 in-app + `EXTRACT(YEAR FROM target_month)` for Lock 11 cron — year-boundary-correctness pattern). **Sec's 9 mods** (2 V1-SHIP-BLOCK + 7 advisory) including: V1-SHIP-BLOCK strict typed-input validation + mass-assignment prevention (§10 meta-pattern instance per Decision 4 — user-facing layer); V1-SHIP-BLOCK numeric-input sanitization battery (NaN/Inf/currency-string regex/overflow/scientific-notation/locale-formatted reject); bracket-row monotonicity DB-trigger; schedule+rows replace-all SERIALIZABLE; SD-04 + SD-11 revisions + new SD-23 planning_target medium; RT-23 + RT-24 medium; `updated_at` UPDATE-refresh trigger via `pfin.fn_refresh_updated_at()` (Sec addendum mod #9 post-initial-ratify); forward-compat fence (no JSONB blobs in settings store under any future surface). **NOT a new instance of §8 cross-tenant FK-bypass family at V1** — settings writes are user-session-bounded; chain becomes live only at V2+ live-tax-API ingestion under service_role (Sec re-consult mandatory at that adoption with Lock 12 mod #2-pattern fence becoming V1-SHIP-BLOCK).

**Cross-references:** locks-log Lock 14; Task #35 Phase 3 carry-over (4 per-domain tables + Zod `.strict()` endpoints + monotonicity + `updated_at` triggers + 9 Sec mods + RT-23 + RT-24 + SD-23). Sec's load-bearing catch: app-layer mass-assignment + numeric adversarial battery at the FIRST user-facing direct DB write path outside §2.4 — §10 meta-pattern (Decision 4) user-facing-surface instance.

### Decision 19 — Lock 15 / Flag #13: as-of-date semantics (Option A — app-layer parameter threading) + Lock 9 amendment

**Locked option:** Option A — app-layer parameter threading; V1 app validates request → bound parameter `$as_of_date`; SQL query uses dual-column filter `transaction_date <= $1 AND created_at <= $1`; SECURITY INVOKER composition helper signature extends with `p_data_as_of DATE`; Lock 13 worker entry gains `data_as_of` as second parameter (cron derives last-day-of-prior-month; on-demand derives CURRENT_DATE or end-of-target_month). **Sec's 9 mods** (2 V1-SHIP-BLOCK + 7 advisory) including: V1-SHIP-BLOCK **Lock 9 amendment — re-introduce `account_trans.created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` IMMUTABLE post-INSERT** (reverses Lock 9 F/CTO correction #3 partially; correction #3 was scope-narrow on event-date immutability; did NOT address row-insertion-time semantics required for §2.3.3 retroactive-edit-historical-view); V1-SHIP-BLOCK app-layer DATE input validation battery (Zod `.date()` + tightened range `2015-12-01 ≤ as_of_date ≤ CURRENT_DATE` per NAV anchor floor + no future dates); server-derived-only fence for §2.6 paths (NO client-asserted `data_as_of` for cron + on-demand monthly_report; §2.3.3 drill-down is the ONLY surface where client toggle is legitimate); Lock 11 mod #2 audit-log shape extension with `data_as_of DATE` field; PDF worker JWT integrity (NO `data_as_of` claim; V1 app reads frozen value from audit-log row); new RT-25 medium (parameter-bypass adversarial input; closes Sec Task #23 forward-looking comment #1). **§10 schema-level orthogonality awareness** (Decision 4 third class) ratified at this lock — drop-column corrections must evaluate against all downstream PRD commitments.

**Cross-references:** locks-log Lock 15 + Lock 9 amendment annotation; Task #36 Phase 3 carry-over (Lock 9 schema amendment + V1 app Zod date-input + SECURITY INVOKER signature + Lock 13 worker `data_as_of` + Lock 11 audit-log extension + PDF worker JWT integrity + 9 Sec mods + RT-25). **ADR-008 amendment** documented per Decision 13 above (Lock 9 correction #3 partial-reversal). Sec's load-bearing catch (8th chain-attack catch this Step): schema-level orthogonality cascade.

### Decision 20 — Lock 16 / Flag #11: cost feasibility (Outcome 1 — confirm ≤$50/month) + candidate P3 disposition (V1-default)

**Locked outcome:** Outcome 1 — V1 fits ≤$50/month under all 15 prior locks; no PRD revision; ADR-002 §6.0 + PRD §7.1 stand. **Cost projection (Architect drill v1.1 after F/CTO clarifications):** fixed-cost section (Plaid per-account-locked + FMP starter + BLS free) $5-$45/mo; already-paid baseline (Hetzner cax21 €9.50/mo per `reference_hetzner_cax21`) $10/mo; feature-dependent (VPS upgrade if needed) $0-$10/mo; **V1 total $15-$65/mo; mid-range ~$35/mo** comfortably under target. Architecture confidence HIGH. **FMP path (a) — keep starter plan** at V1; (b) free-tier + (c) Yahoo/Google scrape captured as V2+ cost-saving levers in BACKLOG. **Candidate P3 disposition (FMP/stock-screening incumbent-exceeds-V1):** V1-default — `pfin_back_etl` ingestion continues unchanged; stock-screening tables accumulate in `pfin_dash`; NO V1 UI surface; V2+ trajectory item in BACKLOG. **PM consult + Sec review SKIPPED** (no scope-cut to vet under Outcome 1; no architectural re-touch; no V1-SHIP-BLOCK security surface introduced). **[Annotation 2026-05-29 — Phase 3 entry gate:** the deferred candidate-P3 PM consult was performed at Phase 3 entry and **confirms the V1-default disposition** ("no V1 UI for FMP/stock-screening; ingestion continues"), closing the skipped-consult gap per the `incumbent-exceeds-V1` guardrail. Disposition unchanged. PM routed two in-band Phase 3 review flags (document the `pfin`↔`pfin_dash` schema boundary in the ingestion architecture; Sec sign-off that the FMP ingestion role cannot reach `pfin` tenant data).**]** **Phase 3 entry-gate tasks:** Plaid production-tier monthly minimum confirmation (sales/onboarding call BEFORE V1 ships); Hetzner cax21 stress-test under full Lock 13 stack; first-quarter actual cost-tracking; V2+ spend-cap / API-quota alerting (PRD §7.1 + App B §7 (a)).

**Cross-references:** locks-log Lock 16; no new Phase 3 task booked (cost-observability operationalized via Phase 3 entry-gate tasks above as Architect Phase 3 implementation work). `reference_hetzner_cax21` + `reference_pfin_back_etl` memories. BACKLOG.md entries: V2+ FMP cost-saving levers (b) + (c); V2+ stock-screening UI surface.

**Consequences.**

- **PRD §1.4 + §7.3 + SECURITY §4.1 axes (i)–(iv) + §4.4 SD matrix + ADR-008 Decision 1 absorb the `tenant_id` → `users_id` rename per Decision 10.** Step 4 close PR sweeps the convention; Phase 3 DDL implementation does the actual column rename.
- **Phase 3 ARCH drafting consumes ADR-011 + the 13 Phase 3 carry-over Tasks** as the V1-mandatory implementation surface. Each task carries its full Sec-mod inventory; Sec re-pings at Phase 3 lock to verify all V1-SHIP-BLOCK mods landed. Phase 3 sequencing: Task #26 (Lock 9 reconciliation; touches schema territory) precedes Task #36 (Lock 15 Lock-9-amendment); Task #32 (Lock 11 monthly_report cron read of owner-id) follows Task #35 (Lock 14 settings table creation).
- **Phase 5 migration design + Phase 6 PR review consume ADR-011 + §SECURITY HTML updates** for V1-mandatory enforcement: every migration touching a SD-NN class implements the storage-protection-class commitment; every PR review against a security-load-bearing surface verifies the §10 defense-in-depth fencing discipline holds (Decision 4); Security Reviewer agent mandatory on every PR touching auth/data/Plaid/secrets per the agent definition.
- **Phase 7 incident handling inherits ADR-008 Decision 4 baseline** (F/CTO-level incident-log primitive at V1; V2 onboarding triggers ramp). No Lock 15 supersession.
- **ADR-008 amendment** for Lock 9 correction #3 partial-reversal: SD-00 row light addendum documents the re-introduced `account_trans.created_at` column per Lock 15 mod #1. Amendment lands at Step 4 close §SECURITY HTML edits PR (PR 2 of 4 in the close-work sequence).
- **§SECURITY HTML edits queued for Step 4 close (PR 2):** SD matrix 14→23 expansion (SD-14 plaid_item_state_history; SD-15 acct_number; SD-16 reconciliation_event HIGH; SD-17 holdings_checkpoint; SD-18 reconciliation_event_trans; SD-12 monthly_report HIGH + child sub-class addendum per Decision 16; SD-23 planning_target per Decision 18; +2 Lock 13 SD entries per Decision 17; SD-04 + SD-11 revisions per Decision 18; SD-00 immutability addendum + Lock 15 created_at addendum per Decisions 14 + 19); RT catalog +10 entries (RT-16 + RT-17 per Decision 13; RT-18 per Decision 14; RT-19 per Decision 15; RT-20 per Decision 16; RT-21 HIGH + RT-22 per Decision 17; RT-23 + RT-24 per Decision 18; RT-25 per Decision 19); RT-13 + RT-09 + RT-10 amendments; §4.2 + §4.3 + §4.6 annotations.
- **PRD HTML edits queued for Step 4 close (PR 3):** §7.3 V1-dormant `account_users` bullet per Decision 6; `users_id` sweep per Decision 10.
- **BACKLOG.md + WORKFLOW.md + MILESTONES.md queued for Step 4 close (PR 4):** BACKLOG entries for V2+ FMP cost-saving levers (b) + (c) + V2+ stock-screening UI surface per Decision 20; V2+ live-tax-API ingestion privileged-context-write surface trajectory per Decision 18; WORKFLOW.md lessons-learned subsection capturing the 8 Sec-load-bearing catches + meta-pattern discovery cycle; MILESTONES.md Phase 1 → complete state + phase-transition prompt invocation per `docs/handoff-prompts.md`.
- **ADR-011 supersedes nothing.** Composes alongside ADR-002 / ADR-003 / ADR-004 / ADR-008 / ADR-009 as the canonical-reference layer for Phase 3 architectural consumption. Per-lock bullet-level rationale lives at `temp/step-4-locks-log.md` (gitignored authoritative state file); ADR-011 captures the decision-grade content at the granularity Phase 3 + Phase 5 + Phase 6 + Phase 7 will consume.
- **Future ADR housekeeping.** When Phase 3 architectural decisions warrant ADR-011 extensions (e.g., per-tenant-key-derivation mechanism for `tenant-scoped-with-app-encryption` classes lands; ARM-tier Postgres tuning under Hetzner cax21 stress-test surfaces a posture refinement), those decisions land at `docs/ARCH/index.html` per ADR-002 §6.0 + §8.0 + Phase 3 territory, not as ADR-011 amendments. When Phase 6 PR-review lessons surface meta-pattern refinements (e.g., a fifth chain-attack family Architect missed but Sec caught), those land as ADR-011 amendments adding to Decisions 1-4 or as new ADR. **ADR-011 canonical-reference layer is intentionally narrow + amendable**; the locks-log meta-patterns plus the 16 per-lock Decisions are the V1-canonical architectural commitments.

**Approved by:** F/CTO (2026-05-26, across the active drilling cycle 2026-05-25 → 2026-05-26 via 16 lock ratifications + 3 mod-set amendments at Locks 14 / 15 / cost-feasibility reframe + candidate P3 disposition).

---

## ADR-010 — Adopt comments-sidecar feature from project_template

**Date:** 2026-05-24
**Status:** Accepted
**Phase:** 1 (Step 4 prep; adopted via [ADR-009](#adr-009) selective-adoption framework)

**Context.** `richmosko/project_template` shipped a per-section HTML doc review feature across four PRs (#8 / #9 / #10 / #11 on the upstream repo, 2026-05-23): an on-disk `docs/<DOC>/comments.md` sidecar with `## §<section-id>` anchors mapping to `<section id="...">` in the HTML doc, a `/refine-doc` skill that walks the sidecar and applies each comment to the matching section (removing addressed comments as it goes), a local Python stdlib HTTP server (`scripts/serve-docs.py`) with a JSON comments API, an in-browser JS widget that lets reviewers add comments inline while reading the doc, and a `/serve-docs` skill that backgrounds the server under the Claude session. The feature is designed for single-user solo review (no author attribution, no threading) and gitignores the sidecar so PR history stays clean. Implementation summary lives at `~/Projects/project_template/temp/comments-implementation.md`.

mosko-fintech is at Phase 1 Step 4 (Architect ratification of PRD content; Phase 3 entry gate) with PRD content migrated to `docs/PRD/index.html` (PR #45) and `docs/SECURITY/index.html` carrying the V1 security canonical reference. Step 4 review is the immediate near-term use case for per-section commenting; Phase 3 ARCH drafting and ongoing SECURITY refinement are downstream use cases.

**Decision.** Adopt the comments-sidecar feature wholesale via two PRs:

1. **Pass 1** (this PR) — convention + `/refine-doc` skill (hand-edit authoring path). Establishes the `comments.md` format, the gitignore entry, the `/refine-doc` skill, and the WORKFLOW.md `Doc review loop` section. Validates the convention via hand-editing before investing in the UX layer.
2. **Pass 2** (next PR) — Python local server (`scripts/serve-docs.py` + `serve-docs.sh`) + JS widget (`docs/_assets/comments.{js,css}`) + `/serve-docs` skill + HTML asset wiring in `docs/PRD/index.html` and `docs/SECURITY/index.html`. Adds the in-browser inline-authoring UX; both passes write to the same on-disk format.

**Why.** Selective-adoption candidate per [ADR-009](#adr-009) Decision 8 (template-as-seed-not-constraint policy): solved problem upstream, modest footprint (~8 new files + 6 edits across 2 PRs), aligns cleanly with mosko's existing `docs/<DOC>/index.html` artifact set and `/start-doc-update` + `/finish-doc-update` skills (PR #42). Strategic timing favors landing before Step 4 review so Architect comments flow through the widget rather than scattering across chat context. Single-user assumption from the upstream design holds for mosko's solo-Founder shape.

**Alternatives considered.**

- **Bundle into one PR.** Rejected — the pass-1 / pass-2 split mirrors upstream's incremental landing pattern and provides a validation checkpoint between the markdown-convention layer and the JS/Python UX layer. Two atomic PRs each independently revertible.
- **Hand-edit-only port (skip Pass 2).** Rejected — per upstream implementation notes, the inline widget is the feature's main UX value-add ("the amazing UX layer") and pays off immediately for solo review. Hand-edit-only would land a working but lower-UX version and likely require the same Pass 2 work later anyway.
- **Defer to Phase 3 (after `docs/ARCH/index.html` is drafted so all three docs get the feature day-one).** Rejected — PRD review at Step 4 is the more pressing use case; ARCH will get the feature automatically once Phase 3 drafts its content. Deferring would forfeit the Step 4 review benefit without a corresponding gain.
- **Merge `comments.css` into the existing `docs/_assets/style.css`.** Rejected — keeping `comments.css` separate matches the upstream `doc.css` + `comments.css` split, produces a cleaner diff (no churn to `style.css` which was lock-edited in PR #38), and makes the feature's CSS surface inspectable in isolation. Two extra `<link>` lines per HTML doc is a trivial cost.

**Adaptations from upstream.**

- **Section-ID examples** in `refine-doc/SKILL.md` use mosko's `sec-N` + `appendix-X` scheme rather than template's semantic IDs (`goals`, `non-goals`). Functional behavior unchanged — section IDs are read from the DOM at runtime and the server-side regex `^[a-z][a-z0-9-]*$` accepts both schemes.
- **`/merge-pr` references dropped** in the suggested PR flow. mosko has no `/merge-pr` skill; merges go through the GitHub UI or `gh pr merge --squash <pr#>`.
- **WORKFLOW.md `Doc review loop` section** rewritten to reference mosko-specific section IDs, phases (Step 4 / Phase 3), and the absence of `/merge-pr`. Pass status note added to make the two-PR landing visible to future readers.

**Approved by:** F/CTO (2026-05-24, via PR plan ratification before PR 1 execution).

**Cross-references:** [ADR-009](#adr-009) Decision 8 (selective-adoption framework). Upstream implementation notes: `~/Projects/project_template/temp/comments-implementation.md` (not in this repo). Template-feedback log location: `temp/project_template_feedback.md` (for any deviations worth contributing back upstream — note that mosko's `<section id>` scheme is one such candidate, since the template's semantic-IDs convention is less mechanically robust than mosko's numeric scheme for handling section renames).

---

## ADR-009 — Selective adoption of richmosko/project_template patterns

**Date:** 2026-05-23
**Status:** Accepted
**Phase:** 1 (Step 4 prep; lands the selective-adoption convention before Phase 3 entry; structural choices for the entire R/P/I+V outer frame going forward)

**Context.** mosko-fintech was bootstrapped through Phases 0 and 0.5 with project-internal conventions: an 8-numbered-phase workflow model, multi-Decision ADR consolidation pattern, monolithic markdown source-of-truth files (`PRD.md`, `WORKFLOW.md`, `DECISIONS.md`), `chief-of-staff` as a spawnable orchestrator subagent, an explicit Visual Designer role separate from UX, and a `/ship-branch` skill encoding mosko-specific PR conventions. By the close of Phase 1 Step 3.5 (v1.30; PR 11), the project had accumulated 14 weeks of locked work across 30+ PRs: a full PRD spanning §1–§8 with three Appendices (114-entry forward-pointer index + 32-entry story trace index), eight accepted ADRs (ADR-002 through ADR-008), and a 298 KB WORKFLOW.md that exceeded Read's 256 KB byte limit (segment-reads only).

F/CTO surfaced `richmosko/project_template` (a reusable Claude Code starter template authored by the same person, distinct from but referenced during mosko-fintech's bootstrap) as a candidate framework for adoption. The template ships an R/P/I/V four-phase model, a nine-specialist roster, an HTML doc-generation pipeline (`/generate-prd` / `/generate-archdoc` / `/generate-secdoc`), a feature-flow scheme (PRD → BACKLOG → Linear → MILESTONES), a `/start-doc-update` + `/finish-doc-update` doc-update flow, and a SessionStart hook that auto-loads only a compact MILESTONES.md head section.

The brainstorm question: does mosko-fintech adopt the template's conventions wholesale, partially, or not at all? Wholesale adoption would invalidate the 14 weeks of locked Phase 1 work (PRD section schema, ADR pattern, agent roster, branch conventions all differ). No adoption would forgo the template's genuine improvements (compact-ledger auto-load model, feature-flow scheme, doc-update skill flow, HTML doc shape with Mermaid). The middle path — **selective adoption with explicit deviations preserved as load-bearing** — emerged early and became the framing throughout. F/CTO formalized the philosophy as `feedback_seed_not_constraint`: "project templates are seed material, not constraints; default to selective adoption + project-specific additions; capture meaningful deviations as feedback to the template repo."

The brainstorm executed across three sessions (2026-05-21 / 2026-05-22 / 2026-05-23) and produced 17 locked structural decisions/sub-decisions. Mid-brainstorm, F/CTO surfaced a layered-persistence question — "are all these decisions getting logged somewhere?" — that produced a working brainstorm log at `temp/template-adoption-brainstorm.md` (gitignored; per `feedback_working_artifacts_temp_not_docs`) and a new memory `feedback_brainstorm_logging` codifying the convention. Six template-feedback entries also accumulated in `temp/project_template_feedback.md` for eventual upstream contribution to `richmosko/project_template`.

This ADR consolidates the 17 brainstorm entries into 9 named Decisions that become canonical references for Phase 3+ work. The bullet-level conventions (CSS class taxonomy, branch-prefix mapping, filename pattern, etc.) elaborated below remain mutable through future revisions if the canonical references hold steady. New convention categories require ADR-009 amendment. This ADR supersedes nothing; it lands the selective-adoption convention as a parallel consolidation alongside ADR-002 / ADR-003 / ADR-004 / ADR-008.

**Decisions.**

### Decision 1 — Agent roster lock

The mosko-fintech agent roster is **main session (acting as team-lead) + 9 specialist subagents**:

| Role | Source | Notes |
|---|---|---|
| **team-lead** | Main session itself (not spawnable) | Absorbs orchestration responsibilities formerly held by spawnable `chief-of-staff` |
| `product-manager` | Both mosko + template | Name aligned |
| `architect` | Both | Name aligned |
| `seceng` | Renamed from mosko's `security-reviewer` | Template-aligned name |
| `ux-designer` | Both | Name aligned; scope is flows + IA only |
| `visual-designer` | **mosko-specific addition** | Owns design tokens, typography, color, spacing; runs palette/typography F/CTO checkpoint; flags missing components back to UX |
| `frontend-lead` | Template (new to mosko) | Phase 5+ |
| `backend-lead` | Template (new to mosko) | Phase 5+ |
| `qa-engineer` | Template (new to mosko) | Phase 5+ |
| `devops-engineer` | Template (new to mosko) | Phase 5+ |

**Dropped from prior roster:**

- **Spawnable `chief-of-staff` subagent.** With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, the main session is addressable like any teammate, so the parallel-orchestration argument for a separate CoS subagent doesn't hold. Removes a confusing duplication where the main session was already operating as CoS and could also spawn one.

**Skipped from template's roster:**

- **`implementation-lead`** (template's CLI / library / ML / data-pipeline generalist). Not applicable to mosko-fintech's full-stack web app shape.

**Visual Designer kept as mosko-specific because** the role encodes load-bearing discipline: a mandatory palette-and-typography checkpoint with the F/CTO before design-system lock, and a "flags missing components back to UX rather than designing around them" boundary that breaks the moment one head holds both roles. The template's single `ux-designer` doesn't encode this discipline. The deviation is logged to the template-feedback log (`temp/project_template_feedback.md` entry: "Visual Designer as a project-specific extension for trust-driven domains") for potential upstream contribution once Phase 2 actually exercises the role.

### Decision 2 — Phase model under R/P/I+V outer frame

Mosko-fintech keeps its 10 numbered phases (0, 0.5, 1, 2, 3, 4, 4.5, 5, 6, 7) and **groups them under template's R/P/I+V outer categories** as a non-destructive labeling addition:

| Outer category (template) | Mosko phases | Notes |
|---|---|---|
| _(Meta-bootstrap)_ | 0, 0.5 | No template equivalent; pre-Research |
| **Research** | 1, 2 | PRD + UX/Visual |
| **Plan** | 3, 4, 5 | Technical Architecture + Project Scoping + Workshop Setup |
| **Implement+Validate** | 4.5, 6, 7 | Agentic Flow Ramp + Build Loop + Deploy & Iterate |

**Linear hierarchy correction:** template's actual hierarchy is **Project → Milestone → Feature** (three scales of the same I↔V loop mechanic). **Sprint is an orthogonal pacing wrapper, not a hierarchy level** — sprint boundaries are bookkeeping events, not I↔V gates.

**Mosko's V1.0 / V1.1 / V1.final / V2 sub-version structure** (PRD §8 / ADR-004) maps to template milestones (Linear Projects). Materialization deferred to Phase 4 (Project Scoping) per ADR-004's "specific sub-version sequencing remains Phase 4 work" and per Decision 7's M1 issue "(c) Populate product milestones."

**Rationale.** Non-destructive: all existing Phase 1 work, ADRs, memory references stay intact. Mosko's finer-grained phases preserve setup-side discipline (PRD vs UX vs ARCH are different activities with different agents); template's R/P/I+V is a clean outer frame for cross-project comparison. Phase 4.5 sits under I+V as "the first I+V loop is a learning loop with throwaway feature as deliverable"; Phase 7 sits under I+V as "ongoing I+V at project scale — V1 done, plan V2."

### Decision 3 — Document format scheme

**HTML format** for product / architecture / security artifacts (diagram-dense, structured-data):

- `docs/PRD/index.html` — converted from `PRD.md` (single-file initial; Layout 1 per-§ split deferred)
- `docs/ARCH/index.html` — new (Phase 3 surface; scaffolded in PR A from template's ARCH.html seed)
- `docs/SECURITY/index.html` — new (receives migrated PRD §4 content per Decision 4)

**Markdown format** for state-ledger and process artifacts (text-shaped, append-only, edit-heavy):

- `MILESTONES.md` — new compact state ledger (auto-loaded per Decision 6)
- `WORKFLOW.md` — conventions (existing; consult-on-demand)
- `DECISIONS.md` — ADRs (existing; consult-on-demand)
- `CHANGELOG.md` — new per-version execution history (consult-on-demand; populated by task #10 extraction)
- `BACKLOG.md` — new (receives migrated PRD §5 content per Decision 4; also serves as Linear overflow queue)
- `docs/MILESTONE-FRAMING.md` — new (receives migrated PRD §8 content per Decision 4)
- `CLAUDE.md` — existing conventions

**Subdirectory shape for HTML docs.** Each top-level HTML doc lives in `docs/<DOC>/` with `index.html` as entry point. Multi-file split (Layout 1 — per-§ files like `01-overview.html`, `02-user-stories.html`, etc.) is the **eventual** target if `index.html` becomes unwieldy; **single-file initial conversion** for now. The subdirectory shape future-proofs growth without preemptive multi-file complexity.

**Rationale.** HTML wins for the artifacts that carry diagrams and structured data (PRD with matrices + 114-entry App B; ARCH with system diagrams; SECURITY with threat models). Markdown wins for artifacts that are text-shaped and edit-heavy (state ledgers, ADRs, changelog). HTML conversion scope is PRD-only for the immediate work; ARCH/SECURITY land via PR A scaffolding + Phase 3 drafting; future state-ledger conversions decided independently per `feedback_orthogonal_decisions`.

### Decision 4 — PRD section schema with relocations

**Mosko's §1–§8 PRD section schema is preserved verbatim.** No new sections are added during the conversion (no dedicated Acceptance Criteria section, no Risks / Open Questions section — both deferred for future consideration if/when they earn their place).

**Three §-relocations** during the conversion (PRD §-stubs become thin pointers to the relocated content):

| Mosko § | Content | Destination |
|---|---|---|
| **§4 Security and compliance posture** | 14-entry SD matrix + 15-entry RT catalog + 6 posture sub-§ | `docs/SECURITY/index.html` |
| **§5 V2 deferred candidates** | ~18 V2 candidates from ADR-002 §2.0 + later additions | `BACKLOG.md` |
| **§8 V1 milestone framing** | V1 sub-version convention + drop-replace migration + Phase 4 handoff | `docs/MILESTONE-FRAMING.md` |

**Sections that stay in PRD verbatim:** §1 Overview, §2 V1 user stories (§2.1–§2.6 archetypes), §3 Success metrics, §6 Out-of-scope, §7 Constraints (§7.1–§7.3), Appendix A (deferred), Appendix B (114 forward-pointers), Appendix C (32 story traces).

**Rationale.** The §1–§8 schema reflects 30+ PRs of deliberate editorial work (Step 3 + Step 3.5); restructuring would re-displace exactly the work the conversion is preserving. The three relocations target sections that will grow over time (Security artifacts as V2 expands; milestone framing touched at every release cycle; V2 candidates accumulate) — separating them into dedicated artifacts is forward-planning at low cost. §5 → BACKLOG.md is template-faithful: forward-looking scope waiting for promotion to Linear is exactly what BACKLOG.md is for in template's feature-flow scheme (Decision 7).

### Decision 5 — HTML doc conventions

Conventions for HTML docs (PRD, ARCH, SECURITY):

**Asset structure** (`docs/_assets/`):

- `style.css` — shared CSS across all HTML docs
- `mermaid.min.js` — **vendored Mermaid runtime, NOT CDN-loaded.** Matches mosko-fintech's fintech security posture (no third-party fetch at view time). Offline-works.

**Filename convention:**

- Number prefix: two-digit zero-padded (`01-`, `02-`, … `08-`)
- Slug: kebab-case, semantic, slugified from §-title
- Appendices: explicit `appendix-a.html`, `appendix-b.html`, `appendix-c.html`
- Index: `index.html` reserved for landing page / TOC (entry point)
- Cross-doc pattern extends: `docs/ARCH/index.html`, `docs/SECURITY/index.html`

**Cross-reference shape:**

- **§-heading anchor IDs:** explicit short IDs from §-numbering (`id="sec-4-5"`, `id="sec-2-4-5"`).
- **Data-entry anchor IDs:** explicit short IDs from existing nomenclature (`id="sd-12"`, `id="rt-13"`, `id="adr-008"`, `id="app-b-rt-13"`).
- **Incidental content anchor IDs:** slugify-derived from heading text.
- **Path style:** relative + anchor. Within-file: `#anchor`. Cross-file within `docs/PRD/`: `02-user-stories.html#sec-2-4-5`. Cross-doc HTML→HTML: `../ARCH/index.html#sec-3-2`. Cross-doc HTML→MD: `../../DECISIONS.md#adr-008` (GitHub-renderable).
- **No `<base href>`.** Anchor IDs are file-agnostic — same `sec-4-5` works whether in `index.html` or `04-security.html` after a multi-file split.
- **Forward-pointer pattern:** §-cell side inline `<a class="forward-pointer" href="#app-b-rt-13">[App B-RT-13]</a>`; App B entry side `<li id="app-b-rt-13" class="active architect-phase-3">…</li>`. Bidirectional navigability.
- **Voting markers / lock markers:** semantic spans — `<span class="vote alpha">Q-S4 α</span>`, `<span class="lock-marker">§4.5 locked 2026-05-18</span>`. CSS color-coding optional polish.

**Structured-data representation:**

- **HTML `<table>`** for fixed-column data: §4.4 sensitive-data matrix (14 rows × 8 cols), §4.5 RLS test catalog (15 rows × 7 cols).
- **Semantic `<ul>` with `<li id="...">`** for variable-content indexed entries: Appendix B (114 entries), Appendix C (32 entries).
- **CSS class taxonomy** (locked vocabulary):
  - **Status:** `.active`, `.resolved`
  - **Classification (5-tag from PR 10):** `.architect-phase-3`, `.sec-v2-implementation`, `.architect-sec-joint`, `.boundary-note`, `.closure-trace`
  - **Tier (§4.4):** `.tier-credential`, `.tier-high`, `.tier-medium`
  - **Severity (§4.5):** `.severity-critical`, `.severity-high`, `.severity-medium`

**Build approach:** no build step initially (option i — accept duplication of headers/footers across files). Promote to templating (build pipeline) only if multi-file adoption expands beyond a single split.

### Decision 6 — Compact-ledger auto-load architecture

**Adopt template's compact-ledger auto-load pattern.** Session-start auto-load reduces to a compact state ledger only; all heavy artifacts become consult-on-demand.

**New auto-load set** (3 files; ~150 lines total):

| File | Mechanism | Purpose |
|---|---|---|
| `CLAUDE.md` (root) | Claude Code built-in | Project conventions, reading order |
| `~/.claude/.../memory/MEMORY.md` | Claude Code built-in | Memory index |
| `MILESTONES.md` (new) | SessionStart hook (read top section above `## Roadmap` cutoff per template's awk pattern) | Compact state ledger: current phase, active feature, milestone summary |

**Removed from auto-load** (all become consult-on-demand):

- `WORKFLOW.md` — was forced-read by re-orient protocol
- `DECISIONS.md` — same
- `PRD.md` / `docs/PRD/index.html` — same
- `ARCHITECTURE.*` — same (when it exists)
- `docs/handoff-prompts.md` — heavily simplified or retired; per-session orient protocol drops; Phase-transition prompts (explicitly invoked) preserved

**Rationale.** Three of six auto-read files exceeded Read's limits at brainstorm time (`WORKFLOW.md` 305 KB byte-limit; `DECISIONS.md` 37K-token-limit; `PRD.md` exceeded both). The previous "always know everything important" auto-load was already silently degraded — segment-reads only. Template's pattern (load slim "where are we" snapshot; consult depth only when work requires it) is the correct shape at the current artifact scale.

**SessionStart hook modification:** modify `.claude/settings.json` to read MILESTONES.md head via template's awk-then-stop pattern (`awk '/^## Roadmap/{exit} {print}' MILESTONES.md`); drop the heavy re-orient protocol that forced reads of WORKFLOW + DECISIONS + PRD + ARCH.

### Decision 7 — Template feature-flow scheme + initial milestones

**Adopt template's feature-flow scheme now** (not deferred to Phase 5 entry):

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

**Initial milestones** (defined in MILESTONES.md):

| Milestone | Status | Gate | Initial issues |
|---|---|---|---|
| **M0 — Research** | Active (virtually done) | PRD locked at end of mosko Phase 1 (after Step 4 ratifies) | Step 3 + Step 3.5 PRs retro-tagged as M0 issues |
| **M1 — Plan** | Pending | ARCH + SECURITY docs locked at end of mosko Phase 3 | (a) Draft ARCHITECTURE; (b) Draft SECURITY (largely landed via ADR-008); (c) Populate product milestones in MILESTONES.md — notes point to `docs/MILESTONE-FRAMING.md`; (d) further granularity TBD |

**Product milestones (V1.0 / V1.1 / V1.final / V2-X) get defined LATER** as the output of M1's issue (c) — the "populate product milestones" work that converts MILESTONE-FRAMING.md's conceptual framing into actual Linear Projects.

**Skill suite phasing:**

- **Adopt now:** `/setup-linear-team` (adapted — must seed M0/M1 meta-process milestones first, NOT PRD §2 stories), `/sync-backlog`, `/cleanup-linear`, `/open-doc`, BACKLOG.md, MILESTONES.md.
- **Adopt at Phase 3 entry:** `/generate-archdoc` (adapted for mosko's existing 87 App B forward-pointers + ADR-008 axes), `/generate-secdoc` (adapted).
- **Adopt at Phase 6 entry:** `/start-feature`, `/finish-feature`, `/merge-pr`.
- **Skip:** `/generate-prd` (PRD already drafted; import mode N/A given conversion path).

**Rationale.** M0 is virtually done — defining it now makes Phase 1 closure cleaner and provides a retro-anchor for Step 3 / 3.5 work. M1 is the natural framing for Phase 3 (ARCH/SEC); the "populate product milestones" issue under M1 makes the deferred Phase 4 (Project Scoping) work explicit and tracked. Adopting feature-flow scheme now (not Phase 5) means Linear + BACKLOG.md infrastructure becomes load-bearing for M1 sub-issue tracking, not just future implementation work.

### Decision 8 — ADR format hybrid policy

**Two ADR patterns are supported in DECISIONS.md going forward:**

- **Consolidation pattern** (mosko's existing — ADR-002 / ADR-008 style): Context → Decisions (numbered multi-Decision structure) → Consequences. Use for: synthesis work, canonical-reference layers, multi-Decision territory establishment.
- **Terse pattern** (template's): `Decision / Why / Alternatives considered / Approved by / Supersedes`. Use for: one-off decisions, simple supersessions, isolated choices.

**Examples:**

- **This ADR (ADR-009):** consolidation pattern. Nine distinct Decisions across roster / phase model / format / schema / conventions / architecture / process — the natural fit for synthesis.
- **ADR-002 / ADR-008:** consolidation pattern (canonical-reference layers).
- **Hypothetical future "use Tailwind for styling":** terse pattern (one-off styling choice).

**Policy location.** `DECISIONS.md` preamble. The hybrid policy is documented in a Format section explaining both patterns and when each applies. The preamble lands as part of this ADR's commit.

**Rationale.** Honors mosko's existing convention (consolidation has proven valuable for canonical-reference work at ADR-002 / 008); allows lean ADRs when work doesn't warrant ceremony. Per `feedback_seed_not_constraint`: template provides the terse pattern as a baseline; mosko preserves the consolidation pattern where it adds value.

### Decision 9 — Doc-update skill flow

**Replace mosko's `/ship-branch`** with template's two-step `/start-doc-update` + `/finish-doc-update` (adapted for mosko).

**`/start-doc-update` adaptation** — phase-prefix map (sub-option 3 hybrid; outer-category names):

| Doc edited | Branch prefix |
|---|---|
| `docs/PRD/*` | `phase/research-<slug>` |
| `docs/ARCH/*`, `docs/SECURITY/*` | `phase/plan-<slug>` |
| Future implementation code | `phase/iv-<slug>` |
| `MILESTONES.md`, `DECISIONS.md`, `BACKLOG.md`, `CHANGELOG.md`, `docs/MILESTONE-FRAMING.md`, `WORKFLOW.md`, `CLAUDE.md`, `.claude/agents/*`, `.claude/skills/*` | `meta/<slug>` |

State-ledger files **lumped under `meta/`** (not split into separate `state/` per template's pattern) — single prefix simpler; doc edited is in the slug.

**`/finish-doc-update` adaptation:**

1. **SSH→HTTPS fallback** ported from retired `/ship-branch` per `feedback_ssh_push_fallback`: per-use-authorization HTTPS temp-switch when SSH push fails; restore origin to SSH after.
2. **Commit format** `docs(<outer>): <subject>` matching the prefix — e.g., `docs(research): add §3.4 metric`, `docs(plan): refine RLS catalog`, `docs(meta): update CLAUDE.md reading order`.
3. **PR body shape** — ported mosko's elaborate shape (Summary / Motivation / Files changed / Test plan / Follow-ups) **replacing template's lean shape.** F/CTO consistently found the richer shape useful for PR review; going lean would be a regression.

**`/ship-branch` retirement:**

- Delete `.claude/skills/ship-branch/`.
- `feedback_ssh_push_fallback.md` memory updated to reference `/finish-doc-update` as the primary path.
- Old branches using legacy `phase/<N>-<descriptor>` or `workflow/<descriptor>` convention stay legacy (no rename); new branches use the adapted convention.

**Rationale.** Template's two-step flow covers branch creation (which mosko did manually) — phase-prefix auto-detection is genuine value-add. Adopting both halves of template's flow lets mosko stop maintaining two competing push+PR paths. Mosko-specific load-bearing pieces (SSH fallback, elaborate PR body) port cleanly into the adapted `/finish-doc-update`.

**Consequences.**

- **ADR-009 supersedes nothing; extends existing convention by selective adoption.** ADR-002 / ADR-003 / ADR-004 / ADR-005 / ADR-006 / ADR-007 / ADR-008 all stand. ADR-009 is parallel to ADR-002 / ADR-003 in shape (consolidation pattern across multiple subjects); parallel to ADR-008 in role (canonical-reference layer for the cross-template-adoption decisions).

- **Phase 3 entry consumption** (Step 4 ratifies → Phase 3 opens). Architect drafts `docs/ARCH/index.html` using template's 9-section ARCH.html seed (adapted with mosko-specific additions: multi-tenant architecture surface per ADR-008 axes i/ii/iii; RLS implementation consuming §4.5 RT catalog; sensitive-data storage architecture consuming §4.4 SD matrix; snapshot regeneration architecture per ADR-008 axis vi; Plaid integration architecture). Architect consumes the 87 active App B forward-pointers + §4.4 + §4.5 + §8 → Phase 4 handoff anchor. Cross-refs use Decision 5's conventions.

- **Phase 4 (Project Scoping) materializes product milestones.** V1.0 / V1.1 / V1.final / V2-X get defined from PRD §8 / `docs/MILESTONE-FRAMING.md` / ADR-004 and become Linear Projects per Decision 7's feature-flow scheme. M1's issue (c) is the trigger.

- **Phase 5+ build work** uses adapted `/start-feature` + `/finish-feature` + `/merge-pr` (Phase 6 entry per Decision 7's skill phasing). `/start-doc-update` + `/finish-doc-update` already active for all doc work per Decision 9.

- **Phase 7 incident handling** per ADR-008 Decision 4 (F/CTO-level incident-log primitive at V1; ramp to formal incident-response shape at V2-trajectory) — unchanged by this ADR.

- **Pending execution tasks** (post-ADR-009 work; tracked at task IDs):
  - **#7** Compact MILESTONES.md ledger (load-bearing for Decision 6; blocks #11 + #15).
  - **#10** Extract changelog from WORKFLOW.md to CHANGELOG.md (orthogonal per `feedback_orthogonal_decisions`; independent timing).
  - **#11** Implement compact-ledger auto-load model (Decision 6 mechanics; blocked by #7).
  - **#12** Migrate PRD §4 → `docs/SECURITY/index.html` (Decision 4; part of PR B).
  - **#13** Migrate PRD §5 → `BACKLOG.md` (Decision 4; part of PR B).
  - **#14** Migrate PRD §8 → `docs/MILESTONE-FRAMING.md` (Decision 4; part of PR B).
  - **#15** Populate MILESTONES.md with M0 + M1 + retro-tag issues (Decision 7; blocked by #7; part of PR C).
  - **#16** Adopt template feature-flow scheme (Decision 7).
  - **#17** Adapt doc-update skills + retire `/ship-branch` (Decision 9; lands on its own `meta/` branch).

- **PR sequence for PRD conversion** (locked per Decision 4's migration staging — Shape B): **PR A** (scaffolding — `docs/PRD/`, `docs/SECURITY/`, `docs/ARCH/`, `docs/_assets/`, skeleton files, conventions locked visibly) → **PR B** (content migration — PRD §1/§2/§3/§6/§7/appendices to HTML; §4/§5/§8 migrations; cross-ref retargeting; archive `PRD.md`) → **PR C** (architectural shift mechanics — populate MILESTONES.md; modify SessionStart hook; simplify/retire `handoff-prompts.md`; update CLAUDE.md). Driver: main session (team-lead) — pure mechanical work, no scope decisions left.

- **Memory updates landed during this brainstorm** (durable behavioral feedback for future sessions):
  - **Updated:** `feedback_subagent_relay_format.md` ([CoS]: → [team-lead]:; roster label refresh); `feedback_ssh_push_fallback.md` (`/ship-branch` → `/finish-doc-update`); `user_role.md` (CoS removed; reading order refreshed); `feedback_main_anchored_orient.md` (auto-read file list refreshed); `feedback_working_artifacts_temp_not_docs.md` (brainstorm-log + template-feedback-log added as examples).
  - **Added:** `feedback_seed_not_constraint.md` (templates are seed not constraint); `feedback_orthogonal_decisions.md` (don't fold orthogonal decisions back into parent framing); `feedback_brainstorm_logging.md` (substantive brainstorms log to temp/ before ADR synthesis).
  - **MEMORY.md index** updated with three new entries.

- **Template-feedback log entries** surfaced for upstream contribution to `richmosko/project_template` (in `temp/project_template_feedback.md`):
  - Visual Designer as a project-specific extension for trust-driven domains.
  - HTML preview methodology should be a per-project decision.
  - Mermaid loading strategy (CDN vs. vendored) should be a template option.
  - Subdirectory structure for HTML docs (`docs/PRD/`, `docs/ARCH/`, `docs/SECURITY/`).
  - Seed default M0 (Research) + M1 (Plan) milestones in template's MILESTONES.md.
  - Distinguish CHANGELOG.md (execution log) from DECISIONS.md (architectural log).

- **ADR-009 canonical-reference immutability boundary.** The nine Decisions are immutable as canonical references for downstream work. Bullet-level conventions inside Decisions (CSS class taxonomy, filename patterns, branch-prefix mappings, etc.) remain mutable through future PRD / ARCH / SECURITY / WORKFLOW revisions if the canonical references hold steady. **New canonical references** (new branch-prefix categories, new file-format categories, new roster roles, new phase categories, new ADR pattern variants) **require ADR-009 amendment.**

- **WORKFLOW.md changelog entry** lands at integration-pass time documenting ADR-009 acceptance + execution-task creation + memory updates + brainstorm log archival path. The changelog entry itself moves to `CHANGELOG.md` upon task #10 execution per Decision 3.

- **Future ADR housekeeping.** When Phase 3 architectural decisions land (V1 stack choices; per-tenant key derivation for `tenant-scoped-with-app-encryption` classes; webhook signature verification mechanism; etc.), those land at ARCHITECTURE.md per ADR-002 §6.0 + ADR-008's Phase-3-territory framing, NOT as ADR-009 amendments. When V2-scoping work surfaces additional template-adoption patterns (additional skills; additional roster roles), new ADRs amend ADR-009. The selective-adoption convention itself (template-as-seed-not-constraint per `feedback_seed_not_constraint`) is intentionally narrow and amendable; the substantive content evolves at the consuming-artifact level.

---

## ADR-008 — Phase 1 Step 3 §4 lock: V1 security posture canonical reference

**Date:** 2026-05-18
**Status:** Accepted
**Phase:** 1 (Step 3; lands the canonical Sec reference layer for PRD §4 Security and compliance posture; closes ADR-002 §7.0 missing-content gaps #4 + #6 + partial close of #5)

**Context.** PRD §4 (Security and compliance posture) was the largest single task in Phase 1 Step 3, drafted with Security Reviewer as primary author for the first time (prior Sec engagements were six at-lock pass-with-comments verdicts on PM-authored §2 sections — §2.1.7 / §2.2.4 / §2.3.5 / §2.4.5 / §2.5.5 / §2.6.6). §4 consolidates material accumulated across §2.4 → §2.6 lock entries: seven Phase 3 RLS test candidates surfaced at §2.6 lock plus seven additional V1-mandatory test surfaces surfaced at gate-B catalog-completion scan (§2.4 + §2.5 + §3 elevations); a thirteen-class sensitive-data inventory plus the explicit baseline class (SD-00) and the cross-cutting derivative-persistence annotation (SD-13); six canonical Sec axes elevated through the six §2.x at-lock passes; three §7-side forward-pointers per §7 routing flag (e); two §3-side Sec routing flags per §3 (d) + (e); accumulated V2-ship-gate Sec-consult flags from §5.4 + §5.6 + §7.1; and the three Q3 self-flags Sec surfaced at gate 1 as required for §4 lock (data retention, availability/uptime, incident handling — closes ADR-002 §7.0 gaps #4 + #5-partial + #6).

The §4 drafting executed under the four-stage two-stage-hybrid drafting pattern ratified at Q4 D-A per the §4 structure proposal gate (pattern divergence (ii)): gate-1 structure proposal; gate-A §4.4 sensitive-data matrix column-shape ratification (Q-Col1 / Q-Class-ID / Q-Tier / Q-Storage / Q-Retention-N); gate-B §4.5 RLS test catalog column-shape + severity-rubric ratification (Q-Catalog-Count / Q-RT-Ord / Q-RT-Col1 / Q-RT-Cat / Q-Sev / Q-Special-Cases); stage-2 row drafting for both consolidation tables; stage-3 posture bulk-closeout for §4.1 + §4.2 + §4.3 + §4.6; stage-4 ADR-008 confirm-or-revise + integration-pass prep. F/CTO ratified 21-for-21 Sec-lean across all gates with zero overrides.

The locked §4 content lands material that will be cited at Phase 3 architecture decisions, Phase 5 migration design, Phase 6 PR review (Security Reviewer mandatory on every PR touching auth / data handling / external APIs / secrets / financial calculations per the Security Reviewer agent definition), and Phase 7 incident handling. ADR-grade canonicality matters for that consumption surface in a way it didn't for §6 (which forward-pointed to ADR-002 §3.0 verbatim) or §7 (which forward-pointed to ADR-002 §6.0 + §1.4 + §5.7). This ADR documents the canonical-reference layer §4 establishes; the bullet-level posture commitments live at PRD §4.1 / §4.2 / §4.3 / §4.6 and remain mutable through future PRD revisions if the canonical references hold steady.

**Decisions.**

### Decision 1 — Six canonical Sec axes as the V1-authoritative set

The V1 security posture is anchored on six canonical Sec axes elevated through the six §2.x at-lock passes (§2.1.7 / §2.2.4 / §2.3.5 / §2.4.5 / §2.5.5 / §2.6.6) and consolidated at §4.1 + §4.3:

- **Axis i — `tenant_id` is the V1 isolation boundary.** Every user-data table carries a `tenant_id` column; every read against a user-data table is RLS-enforced at the database policy layer; multi-tenant infrastructure exercised on the single-user-V1 test path per ADR-002 §1.4. **PRD home: §4.1 bullet 1.**
- **Axis ii — Multi-scope ownership is a tenant-scoped data attribute, NOT an isolation boundary.** The ownership-scope label per ADR-004 Decision B is a `scope` column on user-data rows; scope filtering happens at the application query layer above the RLS boundary. Sixth-consecutive-instance canonical formulation across §2.1.7 → §2.6.6. **PRD home: §4.1 bullet 2.**
- **Axis iii — `tax_treatment` is an inclusion-filter attribute, NOT an isolation boundary.** Same shape as axis ii but for the §2.5 tax-domain attribute per ADR-002 §1.6. Tri-axis query parameterization (`tenant_id × scope × tax_treatment × date`) is the canonical V1 query-shape envelope. **PRD home: §4.1 bullet 3.**
- **Axis iv — Write-path RLS symmetry: write paths inherit the tenant-scoping the read paths enforce.** No V1 write path bypasses the tenant-scoping the read path enforces; manual-entry write paths carry elevated integrity risk distinct from but downstream of the write-path-RLS commitment. **PRD home: §4.1 bullet 4.**
- **Axis v — Staleness-live-read cross-tenant signal leak as new verification surface.** The §2.6.5 live-join-at-render-time pattern (join from snapshot's `account_id` to live §2.4.4 credential-error state) must resolve under requesting-tenant identity, never cross-tenant. **PRD home: §4.3 bullet 1.**
- **Axis vi — Snapshot store as derivative-persistence surface.** Derivative-persistence surfaces inherit storage-protection-class of most-protected source class AND are independently Sec-flaggable for retention-sprawl + blast-radius-widening + render-time-staleness-join compound risk. **PRD home: §4.3 bullet 2 (concrete SD-12 instance) + §4.3 bullet 3 (SD-13 cross-cutting axis).**

The set is closed at V1. New axes surface through V2-scoping work or through Phase 3 / Phase 6 / Phase 7 lessons-learned only via new ADR amendments to ADR-008; PRD §4 body revisions cannot add canonical axes without an ADR-008 amendment.

### Decision 2 — Fourteen-entry sensitive-data classification matrix as V1 canonical classification

PRD §4.4 lands the V1 sensitive-data classification matrix as fourteen entries (SD-00 through SD-13) in §2-traceability order. The column shape (8 columns: Class ID / Class name / Source-§ / Sensitivity tier / Storage protection class / Retention posture / V1-acceptable disclosure surfaces / Phase 3 forward-pointer ID) is canonical at V1 and binds future class additions to the same column shape. Closed-enum columns are:

- **Sensitivity tier (3 values):** `credential` / `high` / `medium`. Three-level rubric per Q-Tier α — matches V1 spread without false-precision tiers for non-existent classes.
- **Storage protection class (4 values):** `credential-class` / `tenant-scoped-with-app-encryption` / `tenant-scoped` / `tenant-scoped-derivative`. Per Q-Storage α — the `tenant-scoped-derivative` value exists specifically for the §2.6-elevated derivative-persistence axis (axis vi).
- **Retention posture (4 values):** `indefinite` / `bounded-Item-active-only` / `bounded-N-day-rolling` / `indefinite-with-V2-cold-storage-rollover`. Per Q3a Option α; the `bounded-N-day-rolling` value applies to SD-02 Plaid Item-state metadata with **N = 90 days** per Q-Retention-N α.

**Cross-cutting annotation cell convention:** rows that are cross-cutting axis annotations rather than concrete classes (SD-13 at V1) use `—` in sensitivity-tier, storage-protection-class, and retention-posture cells; the V1-acceptable-disclosure-surfaces cell carries the axis-as-posture narrative. SD-13 is the only V1 instance; convention applies forward to any future cross-cutting axis annotation at V2+ expansion.

The matrix is closed at V1. New classes surface through V2-scoping work or Phase 3 / Phase 6 / Phase 7 lessons-learned via ADR-008 amendments; new closed-enum values require ADR-008 amendment. Class additions through PRD revision alone (without ADR-008 amendment) are not permitted.

### Decision 3 — Fifteen-entry Phase 3 RLS test catalog as V1-mandatory test surface

PRD §4.5 lands the V1-mandatory RLS test catalog as fifteen entries (RT-01 through RT-15; RT-07 reserved-vacant per stage-2 row-drafting consolidation rationale; 14 active populated tests). Ordering is §2-traceability: §2.4-elevated = RT-01 through RT-05; §2.5-elevated = RT-06 (+ RT-07 vacant slot); §2.6-elevated = RT-08 through RT-14; §3-elevated cross-cutting = RT-15. The column shape (7 columns: Test ID / Surface / Test description / Test category / Source-§ / Severity if violated / Related Class IDs) is canonical at V1 and binds future test additions to the same column shape. Closed-enum columns are:

- **Test category (6 values):** `read-path-RLS` / `write-path-RLS` / `worker-context-isolation` / `input-sanitization` / `race-condition` / `test-environment-posture`. Per Q-RT-Cat α — surfaces the actual mechanism distinctions V1 spans.
- **Severity if violated (3 values):** `critical` / `high` / `medium`. Per Q-Sev α — three-tier rubric parallel to sensitivity-tier discipline.

**V1-block threshold: `critical` severity only.** A `critical` severity test failure or unimplemented test blocks V1 ship; expected V1 critical-severity count = 2 (RT-02 Plaid Item table RLS; RT-05 webhook signature verification). A `high` severity test failure during V1 development is a release-blocker for the V1.x patch release introducing the regression but does not block V1 from shipping if the test was passing at V1 ship; post-ship regression triggers immediate-fix patch release. A `medium` severity test is V1-final-targeted with known-issue tickets acceptable at V1 ship.

The catalog is closed at V1. New tests surface through V2-scoping work or Phase 3 / Phase 6 / Phase 7 lessons-learned via ADR-008 amendments. The bidirectional cross-reference between §4.4 Phase 3 forward-pointer ID column and §4.5 Related Class IDs column is structurally enforced at row-drafting time and validated at stage-2 cross-reference pass.

### Decision 4 — V1 retention / availability / incident-handling posture as baseline (closes ADR-002 §7.0 gaps #4 + #5-partial + #6)

PRD §4.6 lands three V1 posture commitments that close ADR-002 §7.0 missing-content gaps:

- **Data retention posture (closes gap #5 jointly with §2.6.4 χ-1).** Per Q3a Option α. Class-by-class per §4.4 retention-posture column with the canonical values per Decision 2 above. Snapshot-side retention lives at §2.6.4 χ-1 (indefinite per F/CTO lock); non-snapshot retention lives at §4.4 + §4.6. **No user-facing delete-my-data control as V1 surface** — Q3a Option γ rejected at gate 1 as over-shaped for single-user V1.
- **Availability/uptime posture (closes gap #6).** Per Q3b Option α. V1 commits to **best-effort uptime, no SLO**. The V1 user-facing availability story is the §2.4.4 non-silent-staleness commitment — when data is stale, the user is told at every consuming surface. Architect Phase 3 sizes infrastructure-side uptime without PRD-locked numeric per §7.2 + §3 (a) routing.
- **Incident-handling posture (closes gap #4 jointly with the rest of §4).** Per Q3c Option α. V1 commits to an **incident-log file at the F/CTO level**; no on-call rotation, no severity rubric beyond §4.5 Sev-α, no postmortem template at single-user V1. **V2-trajectory ramp to formal incident-response shape if/when the second user lands per §7.3 invite-only forward-compat.**

The three posture commitments are V1 baselines, not specifications. V2-trajectory expansion of any of the three (delete-my-data surface; uptime SLO; formal incident-response shape) requires new ADR or ADR-008 amendment.

### Decision 5 — Two pattern divergences from PM-led default ratified at §4 drafting

The §4 drafting executed under two pattern divergences from the quadruple-confirmed PM-led bulk-closeout pattern (§3 → §5 → §6 → §7):

- **Pattern divergence (i) — Hybrid format.** §4.4 sensitive-data matrix and §4.5 RLS test catalog use markdown tables, not bullet enumeration. Posture sub-sections (§4.1 / §4.2 / §4.3 / §4.6) use the Q2 F-A ratified bulleted-with-framing shape mirroring §5 / §6 / §7. **Rationale:** Phase 3 / Phase 5 / Phase 6 / Phase 7 consume matrices and test catalogs as structured data, not prose; tables are grep-able, can be diffed at V2-expansion, and can be cross-referenced by ID from prose sub-sections.
- **Pattern divergence (ii) — Two-stage hybrid drafting pattern.** Per Q4 D-A. Posture sub-sections bulk-closeout in one body bundle (stage 3); §4.4 and §4.5 draft individually with per-table ratify gates on column shape + severity rubric (gates A + B before stage-2 row drafting). **Rationale:** matrix column-shape decisions (78 / 105 cells per table) are upstream-of-row-drafting and warrant ratification before content drafting, not implicit bundling into body-bundle acceptance.

Future Sec-primary-author sections (none queued in Phase 1; possible at Phase 3 or Phase 6 for ARCHITECTURE.md / migration-design content) may reuse or extend these pattern divergences via reference to ADR-008 Decision 5.

**Consequences.**

- **PRD §4 traces to ADR-008** as the canonical-reference anchor. Future readers seeking the canonical axes / classification matrix / test catalog / severity rubric / retention-availability-incident posture should read ADR-008; §4 body content elaborates the canonical references with bullet-level posture commitments and cross-references to upstream sections.
- **Phase 3 RLS implementation work consumes ADR-008 + §4.5** as the V1-mandatory test surface. Every RLS migration PR cites the relevant RT-NN test(s); Security Reviewer joint-PR-review per §4.1 axis-iv write-path RLS symmetry policy and per the Security Reviewer agent definition's "mandatory reviewer on every PR" scope. Critical-severity tests (RT-02 + RT-05) are V1-ship-blockers per Decision 3; Sec hard-line preserved.
- **Phase 5 migration design + Phase 6 PR review consume ADR-008 + §4.4** as the V1 sensitive-data classification. Every migration touching a §4.4 class implements the storage-protection-class commitment for that class; every PR review against a §4.4 class verifies the V1-acceptable disclosure surfaces commitment holds.
- **Phase 7 incident handling consumes ADR-008 Decision 4** as the V1 incident-handling baseline. F/CTO-level incident-log primitive lives at V1; V2 onboarding triggers the ramp to formal incident-response shape per Decision 4.
- **ADR-008 supersedes nothing; consolidates and extends.** Parallel to ADR-002 / ADR-003 / ADR-004 consolidation shape, distinct from ADR-005 / ADR-006 / ADR-007 surgical-amendment shape. ADR-008 closes ADR-002 §7.0 gaps #4 + #6 + partial-#5 without amending ADR-002's text — the closure is documented in ADR-002 §7.0's traceability surface at integration-pass time (Appendix A absorption deferred to future housekeeping PR per §4 routing flag (o); closure documentation lives at §4 routing flag (o) + §4.6 retention/availability/incident-handling bullets).
- **ADR-008 establishes the immutability-after-acceptance boundary for canonical-reference material.** The six axes, the 14-entry matrix, the 15-entry catalog, the three closed enums (sensitivity tier / storage protection class / retention posture) and the two closed enums in §4.5 (test category / severity), the N = 90 day Item-state retention window, and the three posture commitments (retention / availability / incident-handling) are immutable canonical references. Bullet-level posture commitments at PRD §4.1 / §4.2 / §4.3 / §4.6 remain mutable through future PRD revisions if canonical references hold steady. New canonical references (new axes, new classes, new tests, new enum values, new posture commitments) require ADR-008 amendment.
- **Eleven active routing flags + five boundary notes at §4 lock.** Architect Phase 3 surfaces are: RLS implementation across §4.5 catalog (a); SD-03 Plaid access-token storage shape (b); webhook signature verification (c) Sec/Architect joint; encryption-at-rest evaluation per `tenant-scoped-with-app-encryption` classes (d) — SD-07 sole V1 instance; Item-state metadata 90-day rolling prune mechanism (e); audit-log architecture (f); cron worker tenant-context binding (g); PDF worker tenant-isolation (h); snapshot regeneration race condition (i) Sec/Architect joint; parity-fixture storage and test-environment plumbing (j) Sec/Architect joint. Sec-led V2-ship-gate inventory consolidates four V2-trajectory items (k). Boundary notes (l) through (p) document cross-reference closures.
- **No supersession of any prior ADR.** ADR-002 §1.4 multi-tenant primitive stands; ADR-002 §1.6 tax_treatment three-way tagging stands; ADR-002 §1.7 cost-basis + lot-level deferral stands; ADR-002 §7.0 missing-content gaps #4 + #6 close + #5 partial-close per Decision 4; ADR-002 §8.0 routing flags stand and extend per §4 routing flags (a)–(k); ADR-004 Decision B multi-scope ownership stands and operationalizes at axis ii; ADR-005 settings store stands and operationalizes at SD-04 storage; ADR-006 bracket-aware input layer stands and operationalizes at SD-04 / SD-05 / SD-06 classification; ADR-007 TLH reclassification stands and operationalizes at §4.6 V2-ship-gate inventory item (iii) shared-link delivery §6 advisor-axis re-litigation note.
- **WORKFLOW.md v1.17 changelog entry** lands at integration-pass time documenting §4 lock + ADR-008 acceptance + Sec-lean 21-for-21 track + pattern divergences (i) + (ii) + (iii) all ratified + four-stage two-stage-hybrid drafting pattern executed + §4 closes all Phase 1 Step 3 inventory + Sec posture canonical-reference layer established.
- **Future ADR housekeeping.** When V2-scoping work surfaces (V2 onboarding of the second user per §7.3; V2-trajectory items from §5.4 / §5.6 / §7.1 hitting V2-implementation; V2 derivative-persistence surfaces from §5 deferred candidates), the V2-ship-gate Sec-consults per §4.6 V2-ship-gate inventory produce new ADRs amending ADR-008 (new classes; new test surfaces; new enum values). When Phase 3 architectural decisions warrant Sec posture extensions (e.g., per-tenant-key-derivation mechanism for `tenant-scoped-with-app-encryption` is locked by Architect), those decisions land at ARCHITECTURE.md per ADR-002 §6.0 + §8.0 + Phase 3 territory, not as ADR-008 amendments. When Phase 7 incident-handling lessons surface posture revisions (e.g., the F/CTO incident-log primitive ramps to formal shape pre-V2), those land as ADR-008 amendments to Decision 4. **The ADR-008 canonical-reference layer is intentionally narrow and amendable**; the bullet-level posture content lives at PRD §4 and evolves through PRD revisions if the canonical references hold steady.

---

## ADR-007 — Amendment to ADR-002 Finding (b): tax-loss-harvesting recommendations reclassified from V2+ candidate to permanent non-goal

**Date:** 2026-05-17
**Status:** Accepted
**Phase:** 1 (Step 3; amends ADR-002 Finding (b) per F/CTO 2026-05-17 ratification during §5 V2 deferred candidates structure proposal)

**Context.** ADR-002 Finding (b) enumerates four explicit V2 candidates: Tax planning (estimated payments), Monte Carlo longevity modeling, Lot-level tax features, and Stock screening (with "possibly a separate tool" hedge). The consolidated V2+ deferred list in ADR-002 §2.0 expanded those four into a broader ~18-item enumeration during the Phase 1 Step 2 ratification; that consolidated list specifically named "Lot-level tax features (per 1.7: lot-level UI, FIFO/LIFO/specific-ID matching, wash-sale detection, **tax-loss harvesting**)" — folding tax-loss harvesting under the lot-level-tax-features V2+ banner.

During Phase 1 Step 3 §5 (V2 deferred candidates) structure-proposal review, the §5/§6 axis surfaced TLH recommendations as advisor-shaped rather than observational. The §5/§6 axis is sharp: §5 enumerates capabilities on the eventual product trajectory (locked-as-V2+ in V1 to preserve scope, but anticipated as legitimate later work); §6 enumerates capabilities that are not in this PRD's universe at all (ADR-002 §3.0 permanent non-goals — public sign-up, money movement, advisor / fiduciary role, real-time price quotes, mobile-native app). PM lean at the §5 structure proposal flagged TLH as a §5/§6 reroute candidate with PM-lean toward §6: "TLH as conceived in Finding (b) — recommend a tax-action against a position — is advisory-shaped output, not observational; sits closer to ADR-002 §3.0 advisor-role non-goal than to V2 trajectory."

F/CTO ratified the PM lean 2026-05-17. This ADR documents the amendment.

**Decision.** F/CTO lock 2026-05-17 (per PM-lean Q3a accepted at §5 structure-proposal ratify gate):

**Amendment to ADR-002 Finding (b) (and the §2.0 consolidated V2+ deferred list's "Lot-level tax features" clause):** Remove "Tax-loss harvesting recommendations" from the V2+ trajectory enumeration. TLH is reclassified as **out-of-scope for this PRD lifecycle (§6 home)** under the advisor-role permanent-non-goal axis (ADR-002 §3.0).

**Rationale.** TLH as conceived in Finding (b) — "recommend a tax-action against a position" — is advisory-shaped output. The recommendation is action-prescriptive ("you should sell holding X to harvest a $Y loss against your realized gains"); it implies tax-timing-and-realization advice with a held-position recommendation as its operative output. This crosses the ADR-002 §3.0 advisor / fiduciary role boundary that the V1 PRD treats as a permanent product-identity non-goal — not a deferral, an identity statement.

Distinguishing TLH from the observational tax surfaces that V1 / V2+ legitimately span: §2.5 Estimated Taxes (V1), §3.2 Metric 2 (mixed `tax_treatment` + jurisdictions capability metric), and §3.3 §2.5 parity test all surface tax obligations and computations as **information** ("here's what you owe, here's how much was realized, here's the bracket-aware projection"). TLH would generate **prescriptive recommendations** ("you should sell X to harvest a $Y loss"). The information-vs-prescription axis is what §6's advisor-role boundary protects.

**Distinction from observational tax-tool extensions that REMAIN on the V2+ trajectory list.** Two ADR-002 §1.7 / Finding (b) clauses are retained as V2+ candidates in §5.5 and do not move with this amendment:

- **Lot-level tax features (FIFO / LIFO / specific-ID lot-matching).** These compute cost basis with more precision and provide lot-level reporting surfaces; they do not generate buy / sell recommendations. Remain V2+ in §5.5 per ADR-002 §1.7 + ADR-004 Decision D V2+ enumeration.
- **Wash-sale auto-detection.** Flags wash-sale rule application on existing realized transactions as an informational annotation on past activity; does not recommend future trades. Remains V2+ in §5.5 per ADR-002 §1.7 V2+ enumeration. V1 already ships user-marked wash-sale flag as an information surface; auto-detection is a refinement of that information surface, not a prescription.

The TLH amendment is narrow: only the "recommend tax-actions against unrealized losses" framing is reclassified to §6. Information-surface extensions of the tax domain (more-precise cost basis, more-accurate identification of wash-sale rule application, multi-state expansion, fiscal-year flexibility, etc.) remain V2+ trajectory items.

**§5/§6 placement consequence.** TLH lands in §6 alongside the existing ADR-002 §3.0 permanent non-goals (public sign-up, money movement, advisor / fiduciary role, real-time price quotes, mobile-native app). §6 body drafting in a future thread will enumerate TLH as one of the listed items under the advisor-role axis. §5.5 (estimated-tax deferrals) does not list TLH; this is the body-level consequence of the ADR-007 reclassification and is reflected in the §5 bulk-closeout body landed alongside this ADR.

**Sec note.** ADR-007 carries no new sensitive-data class and no new credential-handling surface. The amendment narrows V2+ scope rather than expanding it; no Sec posture change. (Parallel to ADR-005 / ADR-006 Sec one-line notes for amendment ADRs that don't expand the data or credential surface.)

**Consequences.**

- **PRD §5.5 (V2 deferred candidates — estimated-tax deferrals) does not list TLH.** The §5 body landed alongside this ADR omits TLH from §5.5. Future readers seeking TLH's V1 PRD home should reference §6 (out-of-scope for this PRD lifecycle) and the §6 enumerated permanent-non-goal list under the advisor-role axis.
- **PRD §6 will enumerate TLH at §6 body drafting time.** §6 is currently a stub on PRD.md; §6 drafting in a future thread lands TLH alongside the existing ADR-002 §3.0 permanent non-goals.
- **ADR-002 Finding (b)'s remaining V2+ enumeration stands.** Monte Carlo longevity modeling remains V2+ (landed in §5.5 as observational projection surface per F/CTO Q3b ratify). Stock screening remains V2+ with the "possibly a separate tool" hedge preserved verbatim (landed in §5.5 with hedge per F/CTO Q3b ratify). Tax planning (estimated payments) was already promoted to V1 by ADR-004 Decision D and operationalized by ADR-006; no change. Lot-level tax features remain V2+ minus TLH per this amendment.
- **ADR-007 supersedes nothing; amends ADR-002 Finding (b) specifically.** Parallel to how ADR-005 amended ADR-002 §1.2 (planning targets V1 static reference-value rendering carve-out) and ADR-006 amended ADR-004 Decision D (bracket-aware input layer). Narrow, surgical, with the parent ADR's other clauses unchanged. Future readers should read ADR-002 Finding (b) first, then ADR-007 to layer the TLH reclassification.
- **ADR-007 reinforces the §5/§6 axis-as-product-identity-boundary pattern.** When a V2+ candidate from an earlier ratification turns out on inspection to cross the §3.0 advisor / fiduciary / money-movement / public-distribution / real-time-quote / mobile-native axis, the resolution is to move it to §6 rather than carry it forward as a deferred V2+ trajectory item that the PRD would have to re-litigate at V2-scoping time. The §5/§6 distinction is the V1 PRD's mechanism for keeping product-identity decisions sharp; ADR-007 is the first amendment that exercises that mechanism.
- **No supersession of ADR-002 as a whole.** ADR-007 amends Finding (b) specifically; ADR-002's other findings (a / c / d / e / f) and §1.0 – §8.0 sub-decisions stand unchanged. Cross-reference: ADR-005 + ADR-006 also amended ADR-002 surgically without supersession; ADR-007 follows the same pattern.
- **No new Architect routing flag.** ADR-007 narrows scope; the V1 PRD has no TLH-touching surface to route to Architect Phase 3.
- **Future ADR housekeeping.** If a V2-scoping-phase review revisits ADR-007 (e.g., F/CTO at V2-scoping time wants to consider a tax-loss-harvesting *information* surface that flags wash-sale-eligible loss opportunities as an observational annotation rather than a prescriptive recommendation), that revisit would be a new ADR — not a supersession of ADR-007. The information-vs-prescription axis is the boundary; an information-surface TLH could in principle re-enter V2+ trajectory without violating the §6 advisor-role boundary.

---

## ADR-006 — Amendment to ADR-004 Decision D: V1 input-layer characterization (bracket schedules + tax_character enum)

**Date:** 2026-05-17
**Status:** Accepted
**Phase:** 1 (Step 3; amends ADR-004 Decision D input-layer wording based on F/CTO 2026-05-17 correction surfaced during §2.5 body drafting, plus operationalization of the Sub-Cat tax-character attribute that the §2.5 surface needs)

**Context.** ADR-004 Decision D (2026-05-13) ratified V1 inclusion of estimated quarterly tax payment computation in "primitive form" with the following input-layer characterization: *"Federal marginal rate input"* and *"separate marginal rate input"* for Federal and California FTB. That wording was derived from the 2026-05-13 script audit's reading of the Asset Summary `Est Taxes` sheet (parity-matrix line 80: *"Marginal tax rate input, quarterly estimated payment computation…"*). During §2.5 body drafting, two pieces of evidence required revisiting the input-layer characterization:

1. **F/CTO 2026-05-17 correction on the bracket-aware shape:** F/CTO direct workflow knowledge surfaced that the existing Est Taxes sheet does not use a single marginal-rate input × income; it uses **marginal tax bracket tables + standard deduction**, with realized income for the year plugged into the bracket schedule and tax computed progressively against the deduction. F/CTO quote: *"existing flow with the google sheets has marginal tax brackets and rates listed on the est_taxes sheet. The income for the year get's plugged into that set of tables and estimates the real tax amount based on using the standard deduction. This is more accurate than just plugging in a marginal rate to use…"* The 2026-05-13 audit-derived ADR-004 wording was incomplete — the audit characterization was simplified relative to the actual sheet, and the ADR's "marginal rate input" framing was a re-narration of that incomplete audit reading rather than a deliberate F/CTO scope decision.

2. **§2.5.1 ζ-2 lock on Sub-Cat tax-character attribute:** §2.5.1 body drafting surfaced the need for the per-Sub-Cat tax-character attribute as a V1 input layer alongside the bracket schedules — to route qualified dividends to the Federal LT CG schedule, exclude tax-exempt interest from Federal computation, and provide forward-compat for V2+ tax-character refinements. F/CTO locked ζ-2 at 2026-05-17: a `tax_relevant` boolean + `tax_character` enum with 5 V1 values (`ordinary` / `qualified_dividend` / `tax_exempt_interest` / `long_term_capital_gain_eligible` / `short_term_only`) on each Sub-Cat in the §2.3.1 + §2.2.1 taxonomies.

The audit-derived "marginal rate input" wording would, under a strict reading, justify a less-accurate V1 (single rate × income) than the F/CTO existing system actually uses. A practical reading — anchored in F/CTO direct workflow knowledge — confirms the existing system's bracket-aware computation as the V1 baseline. This ADR documents the amendment.

**Decision.** F/CTO lock 2026-05-17 (per CoS-relayed §2.5 v2 structure proposal + §2.5.1 / §2.5.2 body drafting):

**Amendment to ADR-004 Decision D (two-axis amendment):**

### Axis 1 — V1 input layer: bracket schedules + standard deduction (§2.5.2-scope)

The Decision D input-layer wording "Federal marginal rate input" / "separate marginal rate input" is amended to:

> **V1 input layer (per-jurisdiction bracket tables + standard deduction, user-entered):**
> - Federal **ordinary-income bracket schedule** (multi-row rate + threshold table)
> - Federal **separate LT capital-gains bracket schedule** (typical: 3 rows 0% / 15% / 20%)
> - Federal **standard deduction** scalar
> - California FTB **ordinary-income bracket schedule** (single schedule; CA treats LT capital gains as ordinary income, no separate CA LT CG schedule in V1)
> - California **standard deduction** scalar
> - Single-filing-status V1 (F/CTO's filing status fixed at seed time)
> - **User-entered, manual update at tax-year rollover** — no live tax-data API in V1

**V1 quarterly estimated payment computation is bracket-aware progressive** against these schedules with standard deduction applied to ordinary-routed income before the bracket walk. Live tax-data API ingestion of bracket tables is V2+.

### Axis 2 — V1 input layer: Sub-Cat tax-character attribute (§2.5.1-scope)

Additive to Decision D's input-layer characterization:

> **Each Sub-Cat in the §2.3.1 cash-flow taxonomy and the §2.2.1 asset taxonomy that holds securities subject to capital-gain realization carries:**
> - `tax_relevant` boolean — gates whether the Sub-Cat contributes to §2.5.1 tax-relevant income decomposition
> - `tax_character` enum with 5 V1 values: `ordinary` / `qualified_dividend` / `tax_exempt_interest` / `long_term_capital_gain_eligible` / `short_term_only`

**Federal routing rules per the enum (applied by §2.5.3 computation engine):**

| §2.5.1 column | `tax_character` enum | Federal schedule routed to |
|---|---|---|
| Ordinary Income | `qualified_dividend` | LT CG |
| Ordinary Income | `tax_exempt_interest` | (excluded from Federal computation) |
| Ordinary Income | `ordinary` / `short_term_only` / `long_term_capital_gain_eligible` / default | Ordinary |
| ST CG | any | Ordinary |
| LT CG | any | LT CG |

California FTB routing collapses to a single ordinary schedule per (κ) — all non-excluded contributions route to the CA ordinary schedule.

**Both attributes seeded at V1 bootstrap** from the F/CTO existing system (parallel to ADR-004 Decision C taxonomy seeding) and editable via migration only in V1; user-editable Sub-Cat tax-attribute CRUD UI is V2+ as an extension to §2.3.1 + §2.2.1 broader taxonomy CRUD V2+.

### Decision D "Primitive means" boundary — unchanged

Both axes operationalize Decision D's "Primitive means" framing rather than expanding it. The following remain V2+ per the original Decision D verdict (unchanged by this amendment):

- Multi-state tax handling (any non-California state)
- Non-US tax handling (RRSP, ISA, foreign tax credits, etc.)
- Lot-level tax features (FIFO/LIFO/specific-ID lot-matching; wash-sale auto-detection; Section 1256 auto-detection; tax-loss harvesting recommendations) — per ADR-002 §1.7 + ADR-004 D
- Monte Carlo longevity modeling — per ADR-002 Finding (b)

### F/CTO V1-simplification scope choices (locked alongside ADR-006)

The §2.5 body drafting surfaced two additional V1-simplification scope choices that operationalize Decision D's "Primitive means" framing **without expanding Decision D's V1 scope** (and therefore don't require ADR-006 amendment surface — documented here for decision-history completeness):

- **μ-2 (Realized side at §2.5.3): bracket-derived expected-annual ÷ 4 only; no safe-harbor floor computation in V1.** Tax Balance Prior Year row appears as informational reference only. Safe-harbor computation (Federal 100%/110%-of-prior-year + CA FTB rules) is V2+. F/CTO 2026-05-17 deliberate scope choice for V1 simplicity.
- **ο-a (Unrealized side at §2.5.4): simplified marginal × aggregate G/L per F/CTO Task #2 close verification (2026-05-14).** Federal_LT_CG_top_bracket_rate × `aggregate_unrealized_G/L_taxable` + CA_top_marginal_rate × `aggregate_unrealized_G/L_taxable`. No ST/LT split; no tax_character enum routing on Unrealized; no §2.5.3 engine reuse for Unrealized. **Federal_top_marginal_rate sourced from Federal LT CG top-bracket row per F/CTO 2026-05-17 override** (less-conservative parity choice over PM's conservative-default ordinary top-bracket; aligns with existing-system Est Taxes sheet treatment per F/CTO direct-workflow-knowledge clarification of the Task #2 "marginal-rate" factor). Bracket-aware-as-if-realized refinements (ο-b full / ο-c hybrid-LT-only) are V2+.

**Sec sensitivity note.** Sec at-lock 2026-05-17: *"Sec-class implications: data class #1 (tax-bracket-revealing data — §2.5.2 bracket schedules + standard deduction) sensitivity incrementally higher post-amendment vs. the original Decision D scalar-rate framing; storage / access-control posture unchanged."*

**Consequences.**

- **PRD §2.5 body content traces to ADR-006** for the input-layer scope characterization. The bracket schedules + standard deduction at §2.5.2 + the Sub-Cat tax-character enum at §2.5.1 are direct downstream of ADR-006's two-axis amendment. §2.5.3 computation consumes both axes; §2.5.4 Realized consumes via §2.5.3; §2.5.4 Unrealized under ο-a consumes only the top-marginal-rate values from §2.5.2 (a specific top-bracket row read per jurisdiction, not the full schedule or the tax_character routing).

- **ADR-006 supersedes nothing; amends ADR-004 Decision D specifically.** Parallel to how ADR-005 amended ADR-002 §1.2 — narrow, surgical, with the parent ADR's other clauses unchanged. Future readers should read ADR-004 Decision D first, then ADR-006 to layer the input-layer amendment.

- **ADR-006 reinforces the audit-derived-ADR-text feedback pattern** (memory entry 2026-05-17): when audit notes are re-narrated into ADR text, the resulting ADR wording can over-simplify relative to the actual artifact. The 2026-05-13 script audit reading of the Est Taxes sheet as "marginal rate input" was an over-simplification; F/CTO direct workflow knowledge surfaced the actual bracket-aware computation during §2.5 body drafting. Future ADRs that re-narrate audit findings should be verified against direct artifact inspection at body-drafting time, not assumed to be deliberate scope decisions.

- **PRD §2.5.2 + §2.5.1 settings-store and taxonomy schema additions surface as Architect routing flags** (§2.5 routing-flags block items (a) Sub-Cat tax_character schema, (e) bracket-table-update cadence, (f) §2.5.2 settings store dedup, (g) bracket-schedule routing logic location). Architect Phase 3 picks the implementation shape for both axes; the V1 PRD commitment is the user-facing shape per ADR-006, the storage / query / caching shapes are downstream.

- **§2.5.2 settings store extends §2.3.2 planning-targets settings store per ADR-005.** The richer field shape (multiple bracket rows × multiple schedules × per-jurisdiction × standard deduction scalar, vs. §2.3.2's two scalars) is a new Architect Phase 3 dedup-vs-separate decision. Sec re-engagement on the settings-UI plumbing was already triggered at §2.3.2 lock per Sec Task #23 forward-looking comment #3; §2.5.2 extends the surface additively, not as a new trigger.

- **Sec sensitive-data class #1 (tax-bracket-revealing data) sensitivity upgraded incrementally** post-amendment. The original Decision D scalar-rate framing exposed a single-scalar-per-jurisdiction rate; the amended framing exposes per-jurisdiction multi-row bracket schedules + standard deduction scalar. Sec storage / access-control posture commitment from §2.3.2 settings-UI tenant-scoping carries; no new storage / access-control surface. ADR-006 records this as a Sec-recorded note rather than a new Sec routing flag.

- **No supersession of ADR-004 as a whole.** ADR-006 amends Decision D's input-layer characterization specifically; ADR-004's other Decisions (A target visualization, B multi-scope ownership, C multi-level taxonomy) stand unchanged. ADR-002 amendments via ADR-004 stand unchanged.

- **F/CTO V1-simplification scope choices μ-2 + ο-a documented here for decision-history; not separately ADR-ratified.** μ-2 (safe-harbor V2+ on Realized side) and ο-a (simplified marginal × G/L on Unrealized side) are operationalizations within Decision D's "Primitive means" framing — they don't expand V1 scope beyond what Decision D already authorized, and they pre-existed in F/CTO's existing-system Est Taxes sheet per F/CTO direct-workflow-knowledge. Documenting them in ADR-006 preserves the decision history without elevating them to amendment-shape (they're refinements of Decision D's existing primitive-form scope, not amendments).

- **Future ADRs touching tax-domain inputs route to ADR-006** as the input-layer characterization anchor. Future V2+ amendments (e.g., live tax-data API; multi-state expansion; lot-level features) reference ADR-006 + ADR-004 Decision D as the V1 baseline they're expanding from.

---

## ADR-005 — Amendment to ADR-002 §1.2: planning-targets V1 static reference-value rendering

**Date:** 2026-05-14
**Status:** Accepted
**Phase:** 1 (Step 3; amends ADR-002 §1.2 V1 non-goals based on §2.3 drafting evidence and PDF-inspection of the canonical Finance_Report)

**Context.** ADR-002 §1.2 ratified specific V1 non-goals for spending categorization, including *"budget targets per category, category-level trend charts, custom user-defined categories, recurring-transaction detection, and category alerts/notifications."* During §2.3.2 (cross-account multi-period cash-flow rollup) drafting, two pieces of evidence required revisiting the budget-targets non-goal:

1. **Parity-matrix lines 178 + 199:** the existing Finance_Report renders the Founder/CTO's authored income and expense target values as static caption text under the Income and Expenses section headers, alongside the actual cash-flow totals — used as reference values for visual comparison, not as tracked-budget-with-variance.
2. **F/CTO direct PDF inspection of `Finance_Report_2026_04.pdf` page 6:** confirmed the targets appear as inline caption text ("Pre-tax income from all sources… Target is [value]:" and "Discretionary spending… Budget is [value]:"); no variance computation, no alert mechanic, no per-category target breakdown — only two aggregate values (income target as annual, expense target as monthly).

A strict reading of §1.2's "budget targets per category" non-goal would exclude any V1 rendering of target values. A practical reading — surfaced by the §2.3-drafting evidence — distinguishes between *static reference-value rendering* (parity with existing Finance_Report) and *budget-tracking mechanics* (variance computation, threshold alerts, per-category rolling budgets). The original §1.2 non-goal targeted the latter; the former is parity-preserve.

**Decision.** F/CTO lock 2026-05-14 (Option (a)(i) per CoS-surfaced options framing during §2.3.2 drafting):

**Amendment to ADR-002 §1.2:** the V1 non-goal on "budget targets per category" applies to budget *tracking* mechanics — actual-vs-target variance computation, threshold alerts, category-level rolling budgets, per-category target authoring beyond aggregate values. These remain V1 non-goals.

**V1 includes:** static reference-value rendering of two user-authored aggregate targets (one income target, one expense target) as inline caption text alongside the §2.3.2 cross-account cash-flow rendering — parity-preserve with the existing Finance_Report. **No variance computation, no alert mechanic, no per-category target breakdown.**

**Edit mode (Option (i) per F/CTO lock):** V1 includes a settings UI for user-editing of the two target values — the first concrete V1 surface needing a user-editable settings store. (Alternative considered: seeded-at-bootstrap with edit-via-migration-only — rejected on F/CTO call.)

**Consequences.**

- **PRD §2.3.2** describes the planning-targets caption-text rendering as V1; trace anchors to this ADR for the V1/V2 boundary on tracking mechanics.
- **New V1 settings-UI surface** — introduced solely by this amendment. Architect routing flag #4 in §2.3's Open routing flags block covers the plumbing (generalized settings/preferences table vs planning-targets-specific storage); Sec re-engagement triggered when that plumbing surfaces (per Sec Task #23 forward-looking comment #3 — write-path validation, audit trail, tenant-scoping of the settings store).
- **New Architect flag on planning-targets storage shape** (flag #5 in §2.3's block): likely one income-target total + one expense-target total, period-typed (annual / monthly); Architect Phase 3 confirms.
- **Other §1.2 V1 non-goals unchanged:** category-level trend charts (now partially superseded by §2.3.4 Historical Expenditures expenses-only chart — this is a separate amendment surface, see WORKFLOW v1.9 entry for §2.3.4's "capability not in original parity-matrix V1 enumeration" framing; ADR-005 does not amend the trend-charts non-goal); custom user-defined categories (V2 per ADR-004 Decision C taxonomy CRUD V1/V2 split — already amended); recurring-transaction detection (covered as recurring-vendor inference V1 per §2.3.1 inference-layer lock 2026-05-14 — this is also a §1.2 amendment in shape, captured in §2.3.1's trace + routing-flag #2 not in this ADR); category alerts/notifications (remain V1 non-goal).

**Scope note on §1.2 amendments not in this ADR.** The §2.3.1 recurring-vendor inference V1 inclusion and the §2.3.4 expenses-only time-series chart V1 inclusion are both technically §1.2 amendments in shape (the original §1.2 listed "recurring-transaction detection" and "category-level trend charts" as V1 non-goals). They are not consolidated into this ADR because: (a) §2.3.1's inference layer is a sub-decision within the V1-required transaction-to-bucket assignment UI (the alternative is unworkable per F/CTO's archetype), not a stand-alone V1 surface expansion; and (b) §2.3.4 was caught via PDF inspection as a parity-grounded existing-system surface F/CTO already uses, not a V1 expansion. Their V1/V2 boundaries are documented in the §2.3 PRD section's per-story traces and the §2.3 routing-flags block; this ADR documents only the planning-targets amendment because it introduces a genuinely new V1 user-facing capability (the settings UI) not present in the original ADR-002 §1.2 framing.

---

## ADR-004 — Phase 1 Step 3 script-audit amendments to ADR-002

**Date:** 2026-05-13
**Status:** Accepted
**Phase:** 1 (Step 3; amends ADR-002 ratification verdicts based on a mid-Step-3 functional audit of the Founder/CTO's existing manual-spreadsheet financial system)

**Context.** Phase 1 Step 3 began as PRD section drafting under the original Phase 1 model: preliminary findings → PM-led generative drafting → F/CTO sign-off section-by-section. The §2.1 (net worth) drafting completed and landed on disk under that model. §2.2 (asset allocation) opened with a framing question, and partway into the §2.2 sub-decision sequence the Founder/CTO surfaced an existing two-level asset-categorization taxonomy in active use and declared it a hard V1 backend requirement (with explicit "100% duplicated work to implement a dumbed-down version" reasoning).

That moment exposed a drift: the abstract-from-preliminary-findings drafting was generating requirements the F/CTO already had concrete, system-grounded answers for. The Founder/CTO paused the section-drafting flow and reframed Step 3 around a script-audit-first approach — anchor V1 in functional parity with the existing system, defer to V2 only what F/CTO genuinely doesn't use today, drop only what F/CTO explicitly removes.

Between 2026-05-13 and the same date, the Chief of Staff (with subagent assistance for large-file digesting) audited five artifacts:

1. **`MoskoFinance`** — Google Apps Script with two custom Sheets functions (`calculateHoldings`, `calculateSales`). Holdings + realized-capital-gains compute layer.
2. **Master** Google Sheet — central reference data with 5 load-bearing sheets (`AssetDB`, `AssetPriceHist`, `Asset Categories`, `Cash Flow Categories`, `Account Types`) soft-linked into per-account workbooks.
3. **Fidelity Brokerage (Rich)** — representative per-account workbook with 5 displayed sheets (Summary, Cash Flow, Transactions, Holdings, Sales) and 6 soft-link reference sheets (`_assetdb`, `_assetpricehist`, `_assetcat`, `_cfCat`, `_accounttype`, `_targetaloc`).
4. **Asset Summary** — central cross-account aggregator with 8 in-scope sheets (Account Totals, Nav History, Nav Chart, Asset Allocations, Cash Flow rollup, Est Taxes, `_salesCG`, `_cfMonth`/`_cfQ*`) plus several explicitly-dropped or out-of-scope sheets (Big Ticket Fund, `_Nav_History_MoskoLiu`, `_Est_Taxes_Year`, Account Info, Logins).
5. **Finance_Report** — Google Doc, the canonical V1 deliverable (monthly trust-labeled, full-household-scoped report).

The full audit findings and capability-by-capability V1/V2/drop status are captured in `docs/v1-parity-matrix.md`. This ADR consolidates the four ADR-002 amendments those findings require.

**Decisions.**

### Decision A — Amendment to ADR-002 §1.1: rebalance-target visualization is V1

ADR-002 §1.1 ratified: *"observational allocation visualization is V1; rebalancing suggestions are V2+."* The audit found target-vs-actual allocation with `$ ReAlloc` dollar deltas is currently in active V1-equivalent use across both per-account workbooks (Summary sheet's Asset Allocation Dashboard) and the Asset Summary aggregator (Asset Allocations sheet). The free-text "Rebalancing Targets" section in the monthly Finance_Report is human-curated action commentary derived from this visualization, not generated by the system.

**Amendment:** V1 includes target % vs. actual % allocation visualization with `$ ReAlloc` dollar-delta computation across the allocation surface. This is the visualization-of-the-gap layer. Auto-generated rebalance *suggestions* (system-recommended buy/sell actions) remain V2+ per the original §1.1 intent.

The distinction:

- **V1 (this amendment):** "Your target is 65% equities, you're at 51%, that's $381,642 underweight. Here's the gap as a number." Composes naturally with the multi-level taxonomy (Decision C below) — the gap is visible at top-level Cat and at Sub-Cat resolution.
- **V2+ (unchanged from original §1.1):** "Sell $X of VTI and buy $Y of VOO to bring you into target." The recommendation engine, tax-lot-awareness, account-type-awareness, brokerage-workflow adjacency is the V2 surface.

Monthly Finance_Report's "Rebalancing Targets" free-text commentary is V1-authored-by-user, not auto-generated. V1 ships a free-text field for the user to author monthly action items; auto-generation against the gap visualization is V2+.

### Decision B — Extension to ADR-002 §1.4: multi-scope ownership within multi-tenant

ADR-002 §1.4 ratified multi-tenant-from-day-one with single-user V1 usage and forward-compatibility. The audit surfaced an orthogonal capability not addressed by §1.4: the Founder/CTO has accounts under multiple legal ownership scopes (personal "Rich", "RichMoskoTrust" 2023 trust, retirement custodial accounts IRA/HSA) and tracks allocations and reports by scope. The `RichMoskoTrust Titled?` flag in the Account Info sheet plus six distinct `$ Alloc` columns in Asset Summary's Asset Allocations sheet are evidence of scope-aware data.

**Extension:** ADR-002 §1.4's multi-tenant-from-day-one verdict stands unchanged. Additionally, **the V1 data model supports multi-scope ownership as a first-class attribute on accounts** within a single tenant. Scopes are user-defined ownership labels (examples from F/CTO's system: "Rich personal", "RichMoskoTrust", "Retirement-IRA", "Retirement-HSA"). Allocation and reporting aggregations support scope-filtering.

**V1 default report scope:** full-household (all scopes aggregated). This matches the Finance_Report's current behavior — the document header carries the trust name as administrative identification, but content includes all household accounts regardless of scope.

**V2+ deferred:** per-scope reporting surfaces (one report per scope), scope-aware UI filtering, CRUD UI for managing scopes. Data model supports it from V1; visible product surfaces wait.

Multi-scope ownership is distinct from the household-vs-individual question deferred in ADR-002 §1.4 / §7.0. Households are not in scope (out of PRD lifecycle); multi-scope-within-a-user-household is in scope as a data attribute.

### Decision C — Amendment to ADR-002 §1.8: multi-level user-meaningful asset taxonomy in V1

ADR-002 §1.8 ratified: *"uniform transaction-level handling, security type as categorization attribute, mechanics deferred V2+."* The Founder/CTO's mid-audit input was unambiguous: the existing 6×~35 two-level taxonomy (Cat: Cash / Bonds / Equity / Alternatives / Liabilities / RealEstate × Sub-Cat: FDIC, SIPC, T-bill, CD, IGL, IGI, HYI, INTL, US-01-Basic_Materials through US-10-Utilities, ExUS-Developed_Market, ExUS-Emerging_Market, US-Index_Non_Sector, US-Growth_Non_Sector, REIT, Crypto-Fx, Commodities-Other, Volatility-Hedges, Volatility-60/40, Credit-Balance, EstTaxes-Pending, Loan-Balance, Residential, Commercial, Remodel-Equity, Vehicle, Misc) is a hard V1 backend requirement on the grounds that (a) deferring would create unbounded migration cost (table rewrites), and (b) a single-level surface would be unusable for the V1 instance.

**Amendment:** V1 includes a two-level user-meaningful asset taxonomy (top-level Cat × Sub-Cat). The operationalization is **hybrid** (Option 3 from the Product Manager's pre-pause analysis):

- **V1 data model:** user-scoped multi-level taxonomy tables (one taxonomy per tenant; per-user in V2+ if needed). Forward-compatible for multi-user V2 — no migration debt.
- **V1 seeded with the Founder/CTO's taxonomy** as a migration/seed file at V1 single-user-instance bootstrap.
- **V1 holding-to-bucket assignment UI** — required for V1 active workflow. Users assign holdings to Cat/Sub-Cat buckets through the product, not via direct database access.
- **V1 does NOT ship a user-editable taxonomy CRUD UI** (create / rename / delete categories or sub-categories). Editing the taxonomy in V1 happens via migration / direct database access.
- **V2 adds the editing UI.** Backend is V1-ready; UI is the V2 add.

The original §1.8 verdict's "mechanics deferred V2+" clause stands for securities mechanics specifically (Greeks, intrinsic value, complex lifecycle events for derivatives; YTM, duration, accrued interest for bonds; tax-character decomposition for REITs/MLPs; structured-product specifics). Multi-level taxonomy is not a "mechanic" in that sense — it is a categorization-grammar layer that the existing system has demonstrated is load-bearing.

### Decision D — Amendment to ADR-002 §2.0 (Finding b): estimated quarterly tax payments in V1

ADR-002 §2.0 listed "Tax planning (estimated payments)" as a V2 candidate (Finding b). The audit found the existing Asset Summary contains an `Est Taxes` sheet with: marginal tax rate input, quarterly estimated payment computation, an "IRS" account row tracking actual estimated payments sent vs. estimated obligation, and parallel Federal + State (California Franchise Tax Board) computation tables. The Founder/CTO described this as "works in this primitive form" — sufficient for V1 single-user use, not polished.

**Amendment:** V1 includes estimated quarterly tax payment computation in primitive form:

- Federal marginal rate input
- Federal quarterly estimated payment computation derived from realized income (interest, dividends, bond premiums, capital gains)
- An "IRS" account (or equivalent settable label) for tracking actual estimated tax payments made
- **Parallel California FTB state tax computation** — separate marginal rate input, separate quarterly payment tracking, separate FTB account
- Realized vs Unrealized Tax Liabilities line items derivable from the estimated-tax surface

**"Primitive" means:** V1 supports Federal + California only (the Founder/CTO's jurisdictions). Multi-state tax-engine sophistication, non-US tax handling, lot-level tax features (Federal or state), and tax-loss-harvesting recommendations remain V2+ per the original Finding (b) bucket.

**Remaining ADR-002 Finding (b) items unchanged:** Monte Carlo longevity modeling, lot-level tax features (FIFO/LIFO/specific-ID lot-matching, wash-sale auto-detection, tax-loss harvesting recommendations), and stock screening all remain V2+.

**Consequences.**

- **PRD §2 scope expands.** The §2 user-stories section now needs at least six subsections, not the three originally implied by ADR-002 §1.0:
  - §2.1 Net worth (already drafted; needs extension under Decisions A, B, C and the NAV-with-tax-liability definition)
  - §2.2 Asset allocation (drafted under Decision C operationalization with Decision A `$ ReAlloc` visualization)
  - §2.3 Spending and income categorization (multi-period views, scope-aware aggregations under Decision B)
  - §2.4 Cross-cutting (manual entry, Plaid re-auth, AcctSetup non-cash events, capital gains compute)
  - §2.5 Estimated taxes — **NEW SECTION** per Decision D
  - §2.6 Monthly Report output — **NEW SECTION**; the canonical V1 deliverable

- **Existing on-disk PRD content needs cross-check.** `PRD.md` currently contains §1 (vision + archetype + deferrals) and §2.1 (six user stories). Both were drafted from preliminary findings, not from script-grounded truth. PM cross-checks §1 (specifically §1.2 attribute #4, which a queued reframe addresses) and §2.1 (extend NAV definition, extend headline-delta to multi-horizon × inflation-adjusted, add scope-awareness to the "net worth is mine, not anyone else's" story) under Decision B / Decision C / Decision D context.

- **PRD adds a new §8 — V1 milestone framing.** The expanded post-ADR-004 V1 scope (six §2 subsections plus new capability areas) makes a single "ship V1" event impractical. §8 establishes a V1 sub-version convention (V1.0 → V1.x → V1.final), criteria for what makes each sub-version shippable, and the drop-replace migration pattern (V1.x backend becomes the data source for residual existing-system Google Sheets views during transition, so the Founder/CTO's monthly-finance workflow continues uninterrupted as the data plane shifts underneath). §8 frames the milestone scaffolding; specific sub-version sequencing and per-version capability boundaries remain Phase 4 (Scoping) / Linear-backlog work. §8 also serves as the answer to ADR-002 §7.0 item 7 (*"'V1 done' definition"*): **V1 done = all existing-system capabilities replaced + ADR-004 scope delivered.** PM drafts §8 in late-Step-3, after §1–§7 are substantively settled.

- **`docs/v1-parity-matrix.md` is the V1 capability scope artifact.** PM works from the parity matrix's "PRD §2 mapping" table for what each subsection covers. Open product decisions (the 12-item list in the parity matrix) become the new sub-decision queue PM surfaces to F/CTO one at a time.

- **ADR-002 §8.0 Architect routing flags grow.** The audit surfaced several new Architect items (CPI-U inflation source — manual entry vs. live API; IMPORTRANGE-equivalent cross-account aggregation pattern in V1 SaaS; multi-scope-aware schema; multi-level user-scoped taxonomy data model with seed-on-first-use; live-vs-manual price-source segregation; date-window toggle persistence; freshness/staleness signaling). These get appended to the parity matrix's routing-flag inventory; the PRD references them in the relevant section traces.

- **ADR-002 §6.0 cost target is at risk.** The ≤ $50/month V1 cost target was scoped to a Transactions-only V1. The expanded V1 (Plaid Transactions + Plaid Investments + multi-level taxonomy + estimated taxes + multi-scope data model + monthly-report generation) likely changes the architectural cost shape. Flag for Architect Phase 3 review; the *target* constraint is still F/CTO-policy, but the *bill* gets reconciled in ARCHITECTURE.md.

- **Engagement model: PM resumes section-by-section pacing.** The Founder/CTO has confirmed the per-section sub-decision pacing established in PRD §2.1 drafting continues post-audit. The script audit doesn't change the pacing rhythm — only changes the *grounding* of what PM proposes (script-grounded V1 scope, not preliminary-findings-derived V1 scope).

- **No supersession of ADR-002.** ADR-004 amends specific verdicts; it does not supersede ADR-002 as a whole. The unamended verdicts in ADR-002 stand. Future readers should read ADR-002 first, then ADR-004 to layer the amendments.

- **No supersession of ADR-003.** ADR-003's team-mode engagement pattern is unaffected; team-mode coordination continues to be the Step 3 mechanism. The audit was Chief-of-Staff-led (not PM-led) and proceeded as a CoS-orchestration step within the same team.

- **Future ADR housekeeping:** When PM begins §2 revision, individual sub-decisions that meaningfully alter scope (e.g., NAV definition lock, Rebalancing Targets V1-shape, multi-scope reporting V1-vs-V2) may warrant their own ADR entries. ADR-004 is the consolidated *amendment* ADR; individual *new product decisions* during §2 revision belong in ADR-005 onward.

---

**Date:** 2026-05-11
**Status:** Accepted
**Phase:** 1 (decision made between Step 2 close and Step 3 entry; applies Step 3 onward)

**Context.** Phase 1 Step 2 ratification exercised mosko-fintech's subagent setup at depth: the Product Manager subagent was invoked three times (full ratification report, focused income-categorization V1 check, post-override scope-implication assessment). Two friction points became clear during that work:

1. **No SendMessage available in this harness.** The Agent tool's documented "continue an existing agent" mechanism isn't loaded by default in Claude Desktop. Each PM consultation therefore had to be a fresh spawn with full re-briefing — a real cost when the PM has accumulated 5,000-word ratification context to re-acquire each turn.
2. **Orchestrator-mediated relay has its limits.** Founder/CTO expressed wanting to "meet with the PM" directly, surfacing a gap between the agent-roster vision ("work with my PM") and the subagent mechanic ("one-shot delegations through me as orchestrator"). The CoS-as-relay pattern works but adds friction for any multi-turn agent conversation.

**Claude Code Agent Teams** (experimental, gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) was evaluated as an alternative. Documentation: `https://code.claude.com/docs/en/agent-teams`. A smoke test in Claude Desktop confirmed:

- **Compatibility:** spawn succeeds; teammates load their agent-file system prompts correctly; SendMessage works for lead↔teammate communication; team config persists at `~/.claude/teams/{name}/`.
- **Backend:** in-process only (split-pane requires tmux/iTerm2, which Claude Desktop doesn't provide). Lead and teammates are co-located in one Claude Desktop window; user navigates between them via session cycling.
- Three friction points surfaced during the smoke test; mitigations captured below.

**Decisions.**

1. **Engagement-pattern catalog.** mosko-fintech operates with three subagent engagement patterns, used for different work shapes:
   - **Task mode** — one-shot `Agent` invocation. Used for: a focused deliverable from a single role with no follow-up turns expected. Example uses: Phase 0.5 smoke tests; one-shot research lookups via claude-code-guide; mechanical drafting work.
   - **Meeting mode** — multi-turn back-and-forth with a single persistent subagent. In this harness (no SendMessage at the orchestrator level), this is approximated by re-spawning fresh subagents with re-briefing, accepting the friction. Used for: when one agent needs an extended conversation but other agents aren't involved.
   - **Team mode** — Agent Teams with multiple persistent teammates, peer-to-peer messaging, optional direct user-to-teammate cycling. Used for: multi-agent coordination on a single phase or step, especially when peer consultation between agents (PM ↔ Architect ↔ Security Reviewer) is needed.

2. **Phase-specific engagement model.**
   - **Phase 0:** not applicable (no agents).
   - **Phase 0.5:** task mode (smoke tests of individual agent files).
   - **Phase 1 Step 1–2** (completed under prior model): task mode + approximated meeting mode (orchestrator-mediated, fresh respawn each turn).
   - **Phase 1 Step 3 onward (PRD drafting through phase exit):** **team mode** with PM as workhorse, Architect and Security Reviewer spawn-on-need within the same team.
   - **Phase 2 (UX & Design):** team mode with UX Designer and Visual Designer as primary teammates.
   - **Phase 3 (Architecture):** team mode with Architect as workhorse, Security Reviewer mandatory.
   - **Phase 4 (Scoping):** task mode likely sufficient (PM decomposes; not multi-agent-coordination-heavy).
   - **Phase 5+ (Workshop / Build):** revisit at Phase 5 when build-time agents are defined.

3. **Team-mode operational conventions (smoke-test friction mitigations).**
   - **Agent-file preamble.** Every agent file used as a teammate gets a one-line opening clause at the top of its System prompt section: *"You may be running as a team member. If so, your communication primitive is SendMessage — load it via ToolSearch as your first action before responding to messages from the team lead. Plain-text output is invisible to other team members."* Applied to: product-manager, architect, security-reviewer, ux-designer, visual-designer. Not applied to chief-of-staff (CoS-as-main-session is always the lead, never a teammate).
   - **TaskList not relied upon.** Agent Teams docs reference TaskCreate / TaskUpdate / TaskList as the coordination layer; those tools don't surface in the Claude Desktop harness. Coordination falls back to SendMessage between teammates plus orchestrator-coordinated invocations. The `~/.claude/tasks/{team-name}/` directory may be used for ad-hoc shared files but not as a documented coordination primitive.
   - **Long-context model specified at spawn.** Teammates default to `claude-opus-4-7` (non-1M-context variant). For roles that need to read large composite contexts (PM reading full WORKFLOW + DECISIONS + accumulated PRD; Architect reading full ARCHITECTURE + migrations; Security Reviewer reading full PRD + ARCHITECTURE + source), explicitly specify the 1M-context variant when spawning.
   - **One team per active phase / step.** Team naming convention: `phase-<N>-<step-or-purpose>` (e.g., `phase-1-step-3-drafting`). Created at phase/step entry, torn down at phase/step exit via `TeamDelete` (or direct removal of `~/.claude/teams/{name}/` and `~/.claude/tasks/{name}/` if the calling session lacks team context, as observed during smoke-test cleanup). No cross-phase teams.
   - **Lead is always the orchestrator session (CoS-as-main-session).** The session that calls `TeamCreate` becomes the lead; lead is immutable per the docs. The Chief of Staff role lives in the main session per CLAUDE.md ("default to CoS behavior") and is never spawned as a teammate within its own team.
   - **Experimental flag prerequisite.** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` must be set in `.claude/settings.local.json` (or shell env) at session start. The personal-override settings file is gitignored; not committed.

4. **Fallback to orchestrator-mediated pattern.** Team mode is experimental. If a session experiences team-mode breakage (TeamCreate fails, SendMessage errors, teammates fail to load), the orchestrator-mediated subagent pattern from Step 2 is the fallback — task mode for focused work, approximated meeting mode (fresh respawn with re-briefing) for multi-turn agent work. Fallback isn't a regression; it's the documented backup. Any breakage gets noted in the relevant phase's lessons-learned for future ADR revision.

**Consequences.**

- **Agent files get a preamble edit** applied to PM, Architect, Security Reviewer, UX Designer, Visual Designer. CoS file unchanged.
- **WORKFLOW.md's "Subagent invocation pattern" subsection** in Phase 1 needs a small revision noting that Step 3 onward uses team mode (versus the task-mode pattern used in Steps 1–2). Captured in the same transition commit as the agent-file preambles.
- **Smoke-test artifacts already cleaned up** prior to this ADR: `~/.claude/teams/smoketest-agent-teams/` and `~/.claude/tasks/smoketest-agent-teams/` removed.
- **Per-phase team naming** lets us trace team lifecycle to project phases — e.g., the team for Step 3 drafting will be `phase-1-step-3-drafting`, spawned at Step 3 entry, torn down at Step 3 exit.
- **Experimental-flag dependency** means Founder/CTO must have a Claude Code session running with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` enabled to engage in team mode. The `.claude/settings.local.json` file in this worktree was created for this purpose; a parallel file at the main repo's `.claude/` would enable team mode for main-repo sessions too if F/CTO wants that.
- **A future `docs/agent-engagement.md`** could expand on team-spawn commands, model-selection patterns, troubleshooting. Drafted lazily as patterns emerge during Phase 1 Step 3 rather than upfront.
- **ADR-003 supersedes nothing**; complements ADR-001 (Phase 0.5 process resolutions) and ADR-002 (Phase 1 Step 2 ratification).

---

## ADR-002 — Phase 1 Step 2 ratification of preliminary product findings

**Date:** 2026-05-11 (ratification spanned 2026-05-09 through 2026-05-11)
**Status:** Accepted
**Phase:** 1

**Context.** Phase 1 Step 2 is the ratification pass over the six preliminary product findings captured in WORKFLOW.md → "Project framing → Preliminary product findings" — V1 surfaces, V2 candidates, permanent non-goals, stack, architectural constraints, operating cost expectations. Those findings were captured during Phase 0 as Phase 1 inputs, not as locked product decisions. WORKFLOW.md → Phase 1 → Detailed Steps mandates a focused PM-led ratification pass before PRD section drafting begins: each finding receives one of three verdicts (confirmed, revised, rejected), with revisions and rejections logged as ADRs before drafting. This ADR records the F/CTO-signed-off verdicts for all six findings, plus the accumulated sub-decisions that surfaced during the ratification.

The pass took longer than a single session due to scope expansion within Finding (a) — F/CTO's transaction-tracking scope override (section 1.3 below) triggered a cascade of bounded follow-up decisions and one substantial new V1 product-surface addition (manual non-Plaid accounts and manual transaction entry, section 1.5). The PM agent was invoked three times during this pass: once for the full ratification report, once for a focused income-categorization V1 check, and once for a scope-implication assessment after the transaction-tracking override.

**Terminology clarification adopted during the pass** (per F/CTO refinement, 2026-05-11): items previously labeled "permanent non-goals" are now labeled **"out-of-scope for this PRD lifecycle"** — they will not ship within the current PRD's scope; revisiting them requires an explicit PRD-scope revision. Distinct from **"V2+ deferred"**, which is already anticipated within this PRD as future scope expansion.

**Decisions.**

### Finding (a) — V1 surfaces: revised and substantially expanded

**1.0 — V1 surfaces (ratified, 2026-05-09 through 2026-05-11).** The V1 *initiative* comprises three core user-facing surfaces:

1. **Net worth over time**
2. **Asset allocation visualized against target** (market-value-based, with separate buckets per security type)
3. **Spending and income categorization with monthly per-category summations**

Powered by uniform transaction-level ingest from Plaid Transactions + Investments across depository, credit-card, investment, loan-balance, and crypto-exchange accounts, supplemented by manual non-Plaid accounts and manual transaction entry for holdings Plaid doesn't surface. Implementation boundaries captured in subsections 1.1 through 1.9.

**1.1 — V1 surface splits within Finding (a) (ratified, 2026-05-09).** The original Finding (a) packed two compound capabilities that required splitting:

- "Asset allocation vs. target with rebalancing suggestions" → **observational allocation visualization is V1**; **rebalancing suggestions are V2+** (recommendation engine logic, tax-lot-awareness, account-type awareness, brokerage workflow adjacency).
- "Categorized spending and budget tracking" → **spending and income categorization with monthly per-category summations is V1**; **budget tracking (goal-setting, targets, variance, alerts) is V2+**.

*Considered and rejected:* keeping both rebalancing suggestions and budget tracking in V1 — rejected on scope-discipline grounds; the recommendation engine and goal-setting UI surfaces are each large enough to warrant V2 treatment.

**1.2 — Category summation V1 non-goals (ratified, 2026-05-09).** The following adjacent features are explicit V1 non-goals on the category summations surface, to prevent re-litigation at PRD-drafting time:

- Budget targets per category (already V2+ per 1.1)
- Category-level trend charts
- Category drill-down to transaction list with edit
- Custom user-defined categories
- Recurring-transaction detection
- Category alerts / notifications
- Non-monthly default periods (weekly, quarterly, YTD) — V2+
- Custom user-defined periods — V2+

**1.3 — Transaction-tracking scope expansion (ratified, 2026-05-09; F/CTO override of PM's tight scope guardrail).** PM proposed a tight V1 income/transaction bound limiting V1 to depository-account transactions only. F/CTO overrode on the grounds that depository-only V1 has no viable use case even as a feature-limited product.

**Revised V1 transaction-tracking scope:** mosko-fintech V1 ingests and persists transaction-level activity from Plaid across both depository accounts (checking, savings) and investment accounts (taxable brokerage, IRA, 401(k), HSA where Plaid-supported), via the **Plaid Transactions** product (depository inflows/outflows, credit-card activity) and the **Plaid Investments** product (investment transactions: buy, sell, dividend, interest, transfer, fee, cash; and investment holdings for position-level state). Income recognition in V1 is the union of (a) depository inflows classified by Plaid's transaction categorization and (b) investment-transaction types `dividend` and `interest`. Tax-treatment differentiation is not a V1 calculation requirement, only a stored attribute (per 1.6).

**Transfer tagging** in V1: the system surfaces transactions Plaid flags as transfers (or that the system heuristically pairs across linked accounts) and exposes a per-transaction UI affordance for the user to confirm/override the transfer designation, so transfers are excluded from income and spending aggregations. Auto-detection is best-effort; the user-facing override is the contract.

Plaid Income product remains a V1 non-goal. Manual entry of historical or missing transaction data is available via 1.5 (manual transaction entry) but is not the primary V1 income source.

**1.4 — Multi-tenant V1 (ratified, 2026-05-10).** V1 ships with a multi-tenant data model (tenant_id on user-data tables, RLS policies enforced) and multi-tenant-capable auth infrastructure from day one. The V1 *usage model* is explicitly single-user — UI exercises one tenant, API testing assumes one user, friends-and-family onboarding is not a V1 milestone. **Forward-compatibility commitment:** adding the second user in V2+ requires no data migration of V1 user data.

*Reasoning:* data migrations on real financial data are unbounded-risk operations; the bounded cost of multi-tenant infrastructure from day one is preferable to that risk. *Considered and rejected:* single-tenant V1 with migration when the second user onboards (PM pushback) — rejected on one-way-door reasoning.

**1.5 — Manual-asset and manual-transaction support (ratified, 2026-05-11).** Manual capabilities are in scope for the V1 *initiative* (not V2):

- **Manually-tracked accounts** for non-Plaid assets — car, house, boat, RV, personal holdings, private equity, anything Plaid doesn't surface. Each manual account has a name, type, current value, and updateable value history. Counts toward net worth.
- **Manual transaction entry** on any account (Plaid-connected or manual). Covers: cost-basis overrides, historical backfill predating Plaid's ~24-month window, missed/edited transactions.
- **External valuation integrations** (Zillow, KBB, etc.) are explicit V2-or-later non-goals; V1 manual asset valuation is user-updated.
- **Milestone sequencing** (V1.0 vs V1.1 split) is Phase 4 work; natural split is V1.0 ships with manual *balances* + Plaid-sourced data, V1.1 adds full manual transaction-level entry. Real risk to monitor: V1.1 ending up far enough out that "shippable V1.0" becomes "the product the owner can't really use yet."

**1.6 — Tax-treatment three-way tagging (ratified, 2026-05-10).** Each account is tagged with one of three tax-treatment classifications — **taxable**, **tax-deferred**, **tax-free** — stored as an account-level attribute. V1 income surface includes all dividend/interest income across all account types, undifferentiated for V1 calculation purposes. Tag is available for future V2 surfaces (tax planning, spendable-income views, tax-character splits) without data backfill.

*Flagged for PRD drafting:* HSA's medical-withdrawal constraint may need a sub-flag or a fourth bucket ("tax-free conditional"). Not deciding now.

**1.7 — Cost basis and gain/loss handling (ratified, 2026-05-10 through 2026-05-11).**

**V1 includes:**
- Lot-level cost basis captured at buy time (each `buy` transaction = one lot with its implicit cost basis preserved)
- Aggregate cost basis per position computed from lot data
- Unrealized gain/loss per position (market value − aggregate cost basis)
- Realized gain/loss on sales — uses Plaid-provided `cost_basis` when populated; falls back to average-per-share cost basis with UX-level "estimated" indicator when not
- User cost-basis override mechanism (delivered via 1.5 manual transaction entry capability)

**V1 does NOT include:**
- Per-lot UI (no lot tables, no holding-period indicators)
- Tax-loss harvesting suggestions
- FIFO / LIFO / specific-ID lot-matching for tax purposes
- Wash-sale detection or basis-transfer adjustment

*Flagged for PRD drafting (UX language):* (a) "estimated cost basis" UX label on average-cost-fallback positions, with disclaimer ("Estimated — not for tax filing; consult your 1099-B"); (b) wash-sale caveat in any V1 tax-planning-adjacent surface.

This decision is a meaningful expansion vs. PM's "strict V2 deferral" recommendation. F/CTO's framing: cost basis on buy transactions is implicit (the buy cost itself) and should be logged; aggregate cost basis can be computed with relative ease; unrealized gains follow trivially.

**1.8 — Securities handling general principle (ratified, 2026-05-10).** V1 treats all Plaid-surfaced investment activity uniformly at the **transaction level** — buy, sell, dividend, interest, fee, transfer, cash, etc. — with **security type stored as a categorization attribute** (equity, ETF, mutual fund, derivative, bond/treasury, ADR, crypto, etc.). All positions valued at market value (Plaid's `institution_value`). Asset allocation surface treats different security types as different buckets.

The **underlying mechanics** of complex instruments are explicit V2+ candidates: greeks / intrinsic-value / notional exposure for derivatives; yield-to-maturity / coupon scheduling / duration / accrued interest for bonds; tax-character decomposition for REITs/MLPs; structured-product specifics. Architect feasibility check still needed to confirm Plaid Investments coverage across F/CTO's specific brokerages and instrument types.

This is the scalable framing F/CTO surfaced as a generalization of the options-handling discussion (1.9): treat all Plaid-surfaced security types uniformly at the transaction-and-position level, defer "underlying mechanics" to V2+.

**1.9 — Account-type and transaction-detail decisions (ratified, 2026-05-10 through 2026-05-11).** Per-account-type V1 boundaries:

- **Credit-card accounts:** ingested via Plaid Transactions for the spending surface. Plaid Liabilities product (APR, statement balance, minimum payment, payoff projections) is NOT in V1; deferred to V2+.
- **Loan accounts:** balances ingested via Plaid's standard accounts endpoint for the net-worth liabilities side. Plaid Liabilities product (principal/interest split, escrow, payoff projections) is NOT in V1; deferred to V2+.
- **Brokerage cash sweep / money-market positions:** treated as "cash" bucket in asset allocation; sweep interest counts toward income surface (consistent with the broader interest-income rule). User-configurable per-security allocation classification is V2+.
- **Reinvested dividends (DRIP):** V1 treats Plaid's paired `dividend` + `buy` transactions independently. Dividend counts toward income surface (matches tax reality — DRIP dividends are taxable income). The corresponding `buy` records as a normal investment purchase creating a new lot. No DRIP-pair detection logic in V1. "Income realized in cash" vs "income reinvested" display split is V2+.
- **Tax-deferred account income** (Traditional 401(k)/IRA dividends and interest): included in V1 income surface, undifferentiated by tax treatment in calculations (per 1.6).
- **Options / futures / derivatives:** included under the 1.8 general principle. Tracked at transaction level (buy/sell), valued at market (Plaid's `institution_value`), classified as a "derivatives" bucket in asset allocation. Greeks, intrinsic-value decomposition, complex lifecycle events (assignment mechanics, exercise→shares relationship tracking) are V2+.
- **Bonds and treasuries:** included under the 1.8 general principle. Coupons surface as `interest` transactions (already in V1 income scope per 1.3).
- **Crypto:** included under the 1.8 general principle, for Plaid-supported exchanges (Coinbase confirmed in F/CTO's accounts; others if Plaid adds them). Off-exchange wallet holdings, on-chain transactions, mining/staking-as-income mechanics are V2+.

### Finding (b) — V2 candidates: confirmed

**2.0 — V2 candidates (ratified, 2026-05-11).** The four explicit V2 candidates in Finding (b) are confirmed as stated:

- **Tax planning (estimated payments)**
- **Monte Carlo longevity modeling**
- **Lot-level tax features**
- **Stock screening** (with "possibly a separate tool" hedge preserved verbatim — documents that this V2 line is not a commitment to ship within mosko-fintech, only that it's not V1)

*Reasoning:* prefer a broad V2 candidate list now, whittle down based on V1 learnings rather than pre-judging.

**Consolidated V2+ deferred list (combining Finding (b) with accumulated sub-decision deferrals):**

- Tax planning (estimated payments)
- Monte Carlo longevity modeling
- Lot-level tax features (per 1.7: lot-level UI, FIFO/LIFO/specific-ID matching, wash-sale detection, tax-loss harvesting)
- Stock screening (possibly a separate tool)
- Rebalancing suggestions (per 1.1)
- Budget tracking with goal-setting (per 1.1)
- Non-monthly category periods (weekly/quarterly/YTD) and custom user-defined periods (per 1.2)
- Plaid Liabilities product detail (APR, statement balance, principal/interest split, payoff projections) (per 1.9)
- Plaid Income product (per 1.3)
- External valuation integrations (Zillow, KBB, etc.) (per 1.5)
- Per-security user-configurable allocation classification (per 1.9)
- Derivative underlying mechanics — greeks, intrinsic value, complex lifecycle events (per 1.8, 1.9)
- Bond underlying mechanics — YTM, duration, accrued interest, coupon scheduling (per 1.8)
- Tax-character decomposition for REITs / MLPs (per 1.8)
- Off-exchange crypto wallets, on-chain transactions, mining/staking-as-income mechanics (per 1.9)
- Multi-currency (per 3.0)
- "Income realized in cash" vs "income reinvested" display split for DRIP (per 1.9)
- HSA-specific "tax-free conditional" classification refinement (per 1.6)

### Finding (c) — Out-of-scope items for this PRD lifecycle: revised

**3.0 — Out-of-scope reframing (ratified, 2026-05-11).** Terminology clarification adopted: items previously labeled "permanent non-goals" are now labeled "out-of-scope for this PRD lifecycle." Substance unchanged; the relabel removes the false weight of "permanent" while preserving the discipline (revisiting these items requires an explicit PRD-scope revision, not a casual feature addition).

**Items confirmed as out-of-scope for this PRD lifecycle:**

- **Public sign-up** — fundamentally changes regulatory posture (KYC, fraud, identity verification) and product identity. mosko-fintech is invite-only.
- **Money movement** — initiating transfers, trades, or payments puts mosko-fintech into money-transmitter and/or brokerage territory with significant regulatory implications.
- **Advisor role / fiduciary relationship with users** — becoming a fiduciary requires RIA registration and fiduciary duty obligations.
- **Real-time price quotes** (live tick-level market data) — daily-snapshot data model is the product's data shape; live market data would meaningfully expand both product surface area and data-provider integrations. Technically achievable (F/CTO has existing live price sources) but not load-bearing for any V1 or V2 surface.
- **Mobile-native application** (separate iOS, Android, or React-Native-style app) — the V1 product is delivered as a web application. Mobile-responsive design (web app works correctly in mobile browsers) is expected V1 behavior; specific responsive commitments to be locked during Phase 2 (UX/Design).

**Item reclassified to V2+ deferred:** multi-currency. Multi-currency is not a permanent non-goal — the "in V1" qualifier in the original finding made it a deferral, not an identity statement. Mixing deferrals into the out-of-scope list weakens the discipline of both buckets.

### Finding (d) — Stack: routed out of PRD scope

**4.0 — Finding (d) routed out of PRD scope (ratified, 2026-05-11).** Finding (d)'s content (Supabase, Coolify, VPS, Plaid-as-aggregator, swap-able abstraction layer, frontend framework, background worker architecture) is routed out of PRD scope entirely. Stack is a Phase 3 (Architecture) input. Content migrates verbatim to WORKFLOW.md's Phase 3 inputs list. PRD may reference user-observable consequences of stack choices (e.g., "users access mosko-fintech via web browser") but does not lock the stack itself.

*Reasoning:* per the Product Manager agent's behavioral guideline — *"Never embed architectural decisions in the PRD."* Ratifying this finding for PRD inclusion would either embed architectural decisions in PRD content (violating role boundaries) or lock architectural decisions before the Architect has reviewed them (undermining Phase 3). The Architect agent ratifies this content in Phase 3.

### Finding (e) — Architectural constraints: routed out of PRD scope, with carve-outs

**5.0 — Finding (e) routed out of PRD scope, with carve-outs (ratified, 2026-05-11).** Items routed out of PRD entirely as Phase 3 / Phase 5 territory:

- **Boring monolith** — Phase 3 architectural pattern decision. Migrates to WORKFLOW.md's Phase 3 inputs list.
- **Secrets never in repo** — already authoritative in CLAUDE.md (root); no need to restate in PRD.
- **Migrations in code** — already authoritative in CLAUDE.md (root); no need to restate in PRD.

**Carve-out items previously ratified as PRD-locked product forward-compatibility commitments:**

- Multi-tenant schema from day one — captured in section 1.4 above.
- Lots captured in schema from day one (with lot-level UI deferred to V2+) — captured in section 1.7 above.

### Finding (f) — Operating cost: revised

**6.0 — Operating cost as a PRD-locked constraint (ratified, 2026-05-11).** mosko-fintech V1 is constrained to remain operable at hobby-tier cost — target ceiling **≤ ~$50/month total operating cost** for the V1 single-user-plus-Plaid-data-cost baseline. Specific cost breakdowns (Plaid product pricing, VPS, Coolify, etc.) are Phase 3 outputs in ARCHITECTURE.md, **not** PRD-locked numbers. If Architect cost analysis shows the ≤$50/month target is infeasible given V1's Plaid product mix (Transactions + Investments minimum), the constraint returns to F/CTO for revision before Phase 3 locks.

*Reasoning:* Finding (f)'s original dollar figures ($0/month Trial, $10–40/month family network) were scoped to a Transactions-only V1. The 1.3 transaction-tracking expansion adds Plaid Investments to V1, and Investments is separately metered from Transactions — likely changing the cost shape. The PRD-locked constraint is the cost *target*; the specific dollar bill is an architectural output.

### Missing PRD content gaps: deferred to Step 3

**7.0 — Missing PRD content gaps (deferred to Step 3, 2026-05-11).** Nine content gaps surfaced during ratification that the preliminary findings do not cover. Their resolution is part of PRD section drafting (Step 3), not Step 2 ratification:

1. Sharper target-user definition — user-story-grade specificity needed (persona, finance sophistication, current tools, what they value).
2. Success metrics — what "V1 success" measurably looks like.
3. Trust model and household-vs-individual data — friends-and-family use raises shared-account / household-rollup / strict-siloing questions. Partially constrained by 1.4 multi-tenant ratification.
4. Security and compliance posture scope — needs Security Reviewer pass before lock.
5. Data retention expectations — how long V1 keeps transaction history; delete-my-data control.
6. Offline / availability tolerance — uptime expectations and sync error handling rigor.
7. "V1 done" definition — bar for V1 build phase completion.
8. Accessibility / device support floor — mobile-responsive commitment level; accessibility commitments.
9. Plaid-specific user-facing implications — re-auth flow (Plaid Link expires; tokens need refresh) needs PRD treatment of the user-visible event.

### Routing flags for Step 3 (consolidated)

**8.0 — Architect and Security Reviewer routing flags surfaced during ratification (logged, 2026-05-11).** The following routing flags must be addressed during Step 3 (PRD drafting). Architect flags marked **(F/CTO-led)** indicate F/CTO will own the consultation directly rather than routing through PM.

**Architect routing flags:**

- (F/CTO-led) Plaid product mix and per-product pricing — Transactions, Investments, possibly Auth/Identity for verification (per 1.3, 6.0).
- (F/CTO-led) Sync cadence and webhook architecture for two Plaid products (Transactions + Investments) (per 1.3).
- (F/CTO-led) Holdings-vs-transactions reconciliation strategy and unified transaction-stream data model across depository / credit / investment / loan-balance / crypto account types (per 1.3, 1.8, 1.9).
- (F/CTO-led) Plaid Investments coverage for F/CTO's specific brokerages and instrument types — particularly Treasuries, individual bonds, options (per 1.8).
- Period-aggregation data model: precomputed monthly rollups vs. on-demand aggregation; timezone handling for month boundaries; how categorization recategorization invalidates summaries (per 1.0).
- Income data source boundary: schema must support 1.3's expansion without rewrite when V2 sources are added.
- Asset-allocation persistence model: target allocation storage shape (per 1.0).
- Spending-categorization data model: rule persistence, override persistence, possible merchant-name normalization (per 1.0).
- Multi-tenant infrastructure: RLS policy design that exercises (not bypasses) multi-tenant enforcement on the single-user V1 test path (per 1.4).
- Manual transaction / manual account data model: manual-vs-Plaid-sourced flag on transactions and accounts; conflict-resolution when Plaid contradicts a manual entry; audit trail for user-entered data (per 1.5).

**Security Reviewer routing flags (mandatory before the corresponding PRD sections lock):**

- V1 surfaces section: all three V1 surfaces consume Plaid data; mandatory Security Reviewer pass before lock (per 1.0).
- Multi-tenant carve-out: RLS / data-isolation posture is foundational; mandatory Security Reviewer pass (per 1.4).
- Security and compliance posture section: end-to-end ownership (per 7.0 item 4).
- Broader Plaid OAuth scope and credential surface introduced by Investments product (per 1.3).
- Broader stored-data surface: holdings, position values, tax-deferred account contents; PII implications of holdings data (specific tickers + quantities can identify trading patterns) (per 1.3, 1.9).
- Transfer-tagging UI: user-mutable transaction metadata requires RLS and audit-trail review (per 1.3).
- Manual transaction / manual account write path: user-entered financial data requires different validation/integrity than Plaid ingest (per 1.5).

**Consequences.**

- **V1 scope is materially expanded** vs. the original preliminary findings. The transaction-tracking scope expansion (1.3) and the manual-asset / manual-transaction surface (1.5) are the two largest expansions, both driven by F/CTO product judgment after PM's tighter-scope recommendations were considered and overridden.
- **V1 Plaid product surface** is now Transactions + Investments (minimum) — separately metered. Plaid Liabilities and Plaid Income remain out of V1. Finding (f)'s original Trial-tier $0/month assumption is no longer reliable; the constraint is the *target* (6.0), not the specific bill.
- **The V2+ deferred bucket** has grown to ~18 items beyond Finding (b)'s original four (consolidated list in 2.0).
- **Multiple Architect and Security Reviewer flags accumulated** for Step 3 PRD drafting (8.0); none block ratification but all must be addressed before the corresponding PRD sections lock.
- **Manual-asset / manual-transaction milestone sequencing** is deferred to Phase 4 — natural split is V1.0 ships with manual balances + Plaid-sourced data, V1.1 adds full manual transaction-level entry. Real risk to monitor: V1.1 ending up far enough out that "shippable V1.0" becomes "the product the owner can't really use yet."
- **Terminology refinement** (3.0): "out-of-scope for this PRD lifecycle" vs "V2+ deferred" — two distinct buckets adopted across the PRD.
- **Process refinements surfaced but not formalized in this ADR:** (i) subagent engagement patterns (task mode vs. meeting mode vs. roundtable mode) and (ii) one-question-at-a-time pacing for interactive decision passes. Both warrant a follow-up ADR-003 on subagent engagement, and possibly a `docs/agent-engagement.md` operational reference. Out of scope for ADR-002.
- **WORKFLOW.md updates required as part of phase-exit bookkeeping (Step 6):** preliminary findings subsection replaced with a pointer to PRD; Phase 3 inputs section receives the migrated stack and architectural-pattern items; Phase 1 status to update from "in progress" → "complete" at phase exit (after PRD lock, not now).

---

## ADR-001 — Phase 0.5 process resolutions: PR strategy, agent-file template, smoke-test format

**Date:** 2026-05-08
**Status:** Accepted
**Phase:** 0.5

**Context.** The Phase 0.5 plan flagged three open process choices to be confirmed before drafting the six Phase 1–4 agent files: how to package PRs, whether to lock the proposed agent-file template as-is, and whether to archive smoke-test transcripts. Founder/CTO resolution needed before drafting could begin.

**Decisions.**

1. **PR strategy: one bundled PR for all six agent files.** The roster is reviewed as a set, and landing it atomically matches how WORKFLOW.md frames Phase 0.5 as one phase output. Considered and rejected: one PR per drafting step (4 PRs) — adds review surface without atomicity benefit at this scale.
2. **Agent-file template: locked as proposed.** Header (Phase scope / Reports to / Engagement model / Owns), then sections for System prompt, Behavioral guidelines, Decision rules, Tool scope, Linear permission policy, Handoff & escalation triggers. All six files share this skeleton. Considered and rejected: shrinking before drafting — better to validate the template against concrete content and revisit via lessons-learned at phase exit.
3. **Smoke tests: run live in conversation; not archived.** The value is the live signal that the agent stays in role, not the transcript. Considered and rejected: persisting to `/notes/agent-smoke-tests.md` — premature documentation; if a future phase wants regression checks, build them deliberately.

**Consequences.**

- Phase 0.5 ships as a single PR from `phase/0.5-agent-roster` → `main`.
- Template changes mid-phase must propagate to all already-drafted files. Friction is intentional — discourages template churn once drafting begins.
- No persistent record of smoke tests. Future regression mechanisms must be built deliberately, not mined from chat transcripts.
