# Linear — setup & operating reference

> **Operational how-to** (per [WORKFLOW.md](../WORKFLOW.md) "root docs answer *what and why*; `/docs/` answers *how*"). Linear is the single source of truth for active work — **there is no `TASKS.md`**. This doc captures the as-built workspace topology, the per-agent permission policy, and the milestone-rotation operating model. Landed at Phase 5 Step 7 (Linear MCP setup verification).

**Scope authority:** [ADR-017](../DECISIONS.md#adr-017) Decision 2 (Linear current+next-milestone scope) · [MILESTONE-FRAMING §8.1](MILESTONE-FRAMING.md) (V1 sub-version convention) · WORKFLOW.md Agent Roster (permission scope). Procedure for an actual rotation lives in the [`milestone-rotation`](../.claude/skills/milestone-rotation/SKILL.md) skill.

> **Verification note (Phase 5 Step 7, 2026-06-28).** Drafted across a Linear-MCP outage (safety-classifier unavailability + token expiry mid-step), then **fully verified live on re-auth** — all cells confirmed against the workspace, the write-cycle permission proof completed and reverted. No ⚠️ UNVERIFIED cells remain.

## 1. Workspace topology

| Object | Value |
|---|---|
| **Team** | Mosko-Personal (key `SELF`) — single team, single user (richmosko@gmail.com) |
| **Initiative** | **V1 launch** (status: Planned) → 7 feature-cluster projects |
| **Issue range** | mosko-fintech work = **SELF-181 → SELF-269** (89 issues). SELF-1–180 predate the project (personal/workspace setup). |
| **State (Phase 5)** | **88 mosko issues in `Backlog` + 1 `Done`** — SELF-195 (pgsodium/Vault key mgmt) was closed 2026-06-03 (early dedup/fold-in; overlaps PM Issue 1). Explains the Platform-V1.0 milestone showing 6.25% (1/16) progress. Otherwise pre-build, as expected. |

### Projects (feature clusters) under "V1 launch"

| Project | Issues | PRD cluster |
|---|---|---|
| Platform / Cross-cutting | 28 | ARCH §3–§8 substrate |
| Onboarding / Plaid / Manual entry | 14 | §2.4 |
| Net worth | 15 | §2.1 |
| Asset allocation | 11 | §2.2 |
| Cash flow | 11 | §2.3 |
| Estimated taxes | 7 | §2.5 |
| Monthly report | **0** | §2.6 — V1.5; lives in [BACKLOG §7](../BACKLOG.md), not yet promoted |

(86 of 89 sit in a project; 3 are in the NO-PROJECT bucket — reconcile item.)

### Label taxonomy

- **Role** — `role:backend` · `role:frontend` · `role:arch` · `role:migration` · `role:sec-review` · `role:worker` · `role:fcto` · `role:pm`. **`role:qa` and `role:devops` do not exist** (see §2).
- **Milestone (cross-project tags)** — `V1.0` · `V1.x` · `V1.final`. Coarse tags used to pair a cross-cutting issue with the cluster release it ships alongside. **Distinct from the native project-milestones in §3** — the labels are the cross-project sequencing aid; the native milestones are the per-cluster sub-version objects.
- **Surface** — `surface:auth` · `surface:rls` · `surface:plaid` · `surface:manual-entry` · `surface:pdf-render` · `surface:pfin-etl` · `surface:observability`.
- **Discipline** — `V1-ship-block` · `sec-joint-review` · `conditional-lock-fallback` (per `feedback_conditional_lock_with_named_fallback`) · `plaid-tier-confirmation-dependent`.

## 2. Per-agent permission policy

Per WORKFLOW.md: agents are granted **scoped** Linear access via the MCP server. An agent may **read · comment · update status** (Backlog → Todo → In Progress → In Review → Done) on issues **assigned to its role**. **Reassignment, priority changes, and issue creation outside scope require Founder/CTO action.** Label creation + milestone management are likewise F/CTO-owned (workspace config).

### Per-role scope verification (Step 7)

Decision (F/CTO-ratified): **verify existing-label roles only; defer the rest** to Phase 6 when their first labeled issue lands.

| Role | Representative issue | Read | Comment / status-update |
|---|---|---|---|
| `role:backend` | SELF-269 | ✅ live | ✅ verified* |
| `role:frontend` | SELF-268 | ✅ live | ✅ verified* |
| `role:arch` | SELF-246 | ✅ live | ✅ verified* |
| `role:migration` | SELF-263 | ✅ live | ✅ verified* |
| `role:sec-review` | SELF-269 (dual-labeled) | ✅ live | ✅ verified* |
| `role:worker` | SELF-230 | ✅ live | ✅ verified* |
| `role:qa` | — | n/a | **deferred** — label absent; verify at first Phase 6 QA issue |
| `role:devops` | — | n/a | **deferred** — label absent; verify at first Phase 6 DevOps issue |
| `role:pm` | — | n/a | **deferred** — label exists, tags 0 issues (PM works directly on PRD/BACKLOG artifacts) |

\* *Read scope verified live per-role (`get_issue`/`list_issues`). The **write path** (comment + status-update) was proven end-to-end on SELF-269: posted a test comment + flipped `Backlog → Todo`, both succeeded, then reverted `Todo → Backlog` + deleted the comment (left clean; only `updatedAt` moved). The MCP write mechanism is identical across roles, so one live cycle validates the path; per-role write was not repeated on each issue to avoid gratuitous backlog churn.*

## 3. Milestone model (as-built)

The V1 sub-versions are modeled as **native Linear project-milestones**, one or more per feature-cluster project. **V1.0 spans three milestones** (across Platform, Onboarding, Net worth) — all three must close for the V1.0 release. V1.1–V1.5 are one-cluster-each per the PM-recommended dependency order (the "5-bucket V1.x lock", F/CTO-ratified at Phase 4 Step 4).

| Sub-version | Project · native milestone |
|---|---|
| **V1.0** | Platform → *V1.0 — Platform foundation* · Onboarding → *V1.0 — Onboarding minimal path (full §2.4)* · Net worth → *V1.0 — §2.1.1 current NAV* |
| **V1.1** | Net worth → *V1.1 — Net worth full (§2.1.2–§2.1.7)* |
| **V1.2** | Asset allocation → *V1.2 — Asset allocation full (§2.2)* |
| **V1.3** | Cash flow → *V1.3 — Cash flow full (§2.3)* |
| **V1.4** | Estimated taxes → *V1.4 — Estimated taxes full (§2.5)* |
| **V1.5** | Monthly report → *V1.5 — Monthly report full (§2.6)* — milestone shell exists; **0 issues** (the [BACKLOG §7](../BACKLOG.md) promotion target) |
| **V1.x** | Platform → *V1.x — Cross-cutting infra (intermediate)* — catch-all; issues here pair with a V1.1–V1.5 cluster via the `V1.x` label |
| **V1.final** | Platform → *V1.final — §3.4 close mechanism* — V1-done close per PRD §3.4 + MILESTONE-FRAMING §8.3 |

### Rotation operating model

Per [ADR-017](../DECISIONS.md#adr-017) Decision 2, Linear holds **current + next milestone + always-active Platform/Cross-cutting**; everything further out lives in [BACKLOG §7](../BACKLOG.md) until promoted at rotation. The full procedure (verify-completion → rotate next→current → promote §7→Linear → update ledger/CHANGELOG) is the [`milestone-rotation`](../.claude/skills/milestone-rotation/SKILL.md) skill.

**As-built note:** because V1.0–V1.4 native milestones already exist in Linear (created at Phase 4 decomposition), the going-forward §7→Linear promotion first bites at **V1.5 (Monthly report)** — its milestone shell exists but its 18 BACKLOG §7 issues (8 Architect substrate A1–A8 + 10 PM domain P2–P11) are not yet created. That is the genuinely-untested promotion path the rotation rehearsal targets.

### Step 7 rotation rehearsal — dry-run verdict

Read/verify only (no mutations), per F/CTO Decision A:

- **Gate behavior validated against a partially-complete milestone.** `milestone-rotation` Step 0 requires *every* current-milestone issue to be `Done` before rotating. The `V1.0 — Platform foundation` milestone is **1/16 Done** (SELF-195) with 15 still `Backlog` → **not all Done → the rotation gate correctly does NOT proceed.** Testing against a 6.25%-complete milestone (rather than a pristine all-Backlog one) is a stronger guard check: partial progress must not trip an early rotation.
- **§7 promotion set confirmed** = 18 entries in [BACKLOG §7](../BACKLOG.md) (cross-checked against the live file). The V1.5 milestone shell is the destination; promotion = create-issues-from-§7-specs + attach to that milestone + mark §7 entries "Promoted to Linear at SELF-N".
- **No live rotation executed** — nothing has completed; the rehearsal exercises only the read/verify path, as intended.

## 4. Known gaps / reconcile-later

| # | Item | Disposition |
|---|---|---|
| 1 | ~~Asset allocation milestone name~~ | ✅ **Resolved** — confirmed *V1.2 — Asset allocation full (§2.2)*. |
| 2 | ~~Platform V1.0 progress = 6.25%~~ | ✅ **Resolved** — SELF-195 (pgsodium/Vault key mgmt) is `Done` (closed 2026-06-03, early dedup/fold-in vs PM Issue 1). 1/16 = 6.25%. The scout's "all 89 Backlog" tally was off by this one issue. |
| 3 | **`role:qa` + `role:devops` labels absent** | Open — not created at Phase 4. Defer to Phase 6: create when each role's first issue is decomposed (F/CTO action). |
| 4 | **`role:pm` label unused** | No action — PM works on PRD/BACKLOG artifacts, not labeled execution issues. |
| 5 | **3 mosko issues in NO-PROJECT bucket** | Open — identify and attach to their cluster project (low priority; cosmetic). |
| 6 | **Granularity framing in ADR-017 D2 vs labels** | ✅ **Resolved as a non-issue** — native project-milestones faithfully represent per-sub-version units (V1.0–V1.5 + V1.final); the coarse `V1.0/V1.x/V1.final` **labels** are a complementary cross-project sequencing aid, not a competing model. No doc reconciliation needed. |
| 7 | ~~Live write-cycle permission proof~~ | ✅ **Resolved** — verified on SELF-269 (comment + status flip, then reverted; see §2). |
