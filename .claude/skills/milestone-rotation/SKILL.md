---
name: milestone-rotation
description: Operationalizes the V1 milestone-rotation procedure per ADR-017 Decision 2. Invoke when the current milestone's last V1-SHIP-BLOCK gate passes — all Linear issues for that milestone are Done and the V1-SHIP gate closes. Covers: verifying completion against live Linear (not memory), rotating next→current, promoting the milestone-after-next from BACKLOG.md §7 to Linear verbatim (Source/AC/Dependencies carried), marking §7 entries "Promoted to Linear at SELF-N", updating MILESTONES.md compact ledger (5-entry per ADR-017 Decision 1), and landing the 1-sentence MILESTONES entry. Writes no CHANGELOG entry -- that file is frozen.
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Bash
  - mcp__claude_ai_Linear__list_issues
  - mcp__claude_ai_Linear__save_issue
  - mcp__claude_ai_Linear__list_milestones
  - mcp__claude_ai_Linear__get_milestone
  - mcp__claude_ai_Linear__list_projects
  - mcp__claude_ai_Linear__list_teams
---

# milestone-rotation — V1 milestone-rotation procedure

Use when the current V1 milestone's last feature merges and the V1-SHIP gate closes. The procedure is the formal handoff between one milestone's implementation phase and the next: it updates the live work-tracking layer (Linear), and the repo state ledger (MILESTONES.md) in one bounded operation. DevOps owns the Linear workspace mechanics; Architect owns any migration sequencing that blocks a promoted issue; Security Reviewer is mandatory consult on §7 entries that carry a "Sec joint-review mandatory" tag before their first Linear issue is created.

mosko-fintech skill (DevOps-owned). Operationalizes [ADR-017](../../../DECISIONS.md#adr-017) Decision 2 (Linear current+next-milestone scope) and Decision 1 (MILESTONES.md compact-ledger convention). Phase 5 Step 7 rehearsal target.

## Canonical authority

**[ADR-017](../../../DECISIONS.md#adr-017) Decision 2** (read verbatim before executing — brief-drift-catch discipline):

- **Linear holds:** the milestone currently being implemented + the next milestone in sequence + Platform / Cross-cutting V1.x (foundational substrate, always active).
- **BACKLOG.md holds:** all other planned milestones, with full Source / Acceptance criterion / Dependencies specs at Linear-grade granularity.
- **Promotion mechanism:** when implementation of the current milestone completes, the next milestone rotates into "current" and the milestone after it gets promoted from BACKLOG.md to Linear ("next"). Promotion = creating Linear issues from the BACKLOG.md specs verbatim, then marking the BACKLOG.md entries as "Promoted to Linear at SELF-N" (durable historical reference).
- **Going-forward only.** Existing V1.0–V1.4 issues already in Linear (89 issues; SELF-181 → SELF-269) stay in Linear. Wave 6 (V1.5) onward lands new decompositions in BACKLOG.md. V1.5 + V1.final are staged in BACKLOG.md §7 (18 entries: 8 Architect substrate §7.1 A1–A8 + 10 PM domain §7.2 P2–P11; last-updated 2026-06-03).

**[ADR-017](../../../DECISIONS.md#adr-017) Decision 1** (MILESTONES.md compact-ledger convention): last 5 entries; 1 sentence per entry naming deliverable + key F/CTO ratify + headline metric; ⚠ each entry USED TO end with `Detail: [CHANGELOG vN.NN](…)`; it no longer does, because `CHANGELOG.md` is frozen (see `WORKFLOW.md` § Artifact list). Name the PR instead — GitHub keeps the detail. Oldest entry rotates out when at 5.

## Step 0 — verify before touching anything

1. Read BACKLOG.md §7 verbatim (`Read /Users/mosko/Projects/mosko-fintech/BACKLOG.md` offset at §7) to get the live promotion set. Do not rely on cached counts or memory — §7 entry count and SELF-N assignment depend on what actually shipped in Linear, which may have changed since last read.
2. Call `list_issues` filtered to the current milestone. Confirm every issue is in a "Done" state. If any issue is not Done: stop. Surface the open issues to F/CTO; do not rotate.
3. Call `list_milestones` to confirm the "next" milestone name and its current Linear state. Note: V1.0–V1.4 are already in Linear per the going-forward carve-out; the first BACKLOG.md §7 promotion triggers when V1.3 completes (V1.5 becomes "next") and again when V1.4 completes (V1.final becomes "next").

## Step 1 — rotate next → current

4. Update tracking in MILESTONES.md "Current Phase" table: the milestone that was "next" is now "current"; note the rotation date. Do not close any Linear issues that are not Done — the verify step (Step 0) is the gate.
5. No Linear milestone status changes needed at this step — Linear milestones are project-level containers; the rotation is an MILESTONES.md + BACKLOG.md state event, not a Linear project rename.

## Step 2 — promote milestone-after-next from BACKLOG.md §7 → Linear

6. Read the §7 entries for the milestone being promoted. For each entry:
   a. Call `save_issue` with title, description (Source + AC verbatim), and team/project context from `list_teams` / `list_projects`. Match the field structure a V1.0–V1.4 Linear issue would carry — do not abbreviate Source or AC content; the spec is the contract.
   b. Record the assigned SELF-N number (Linear issue ID) returned by `save_issue`.
7. After all issues are created, edit BACKLOG.md §7 to mark each promoted entry: append **Promoted to Linear at SELF-N** inline after the entry title (durable historical reference per ADR-017 Decision 2).
   - Verify the SELF-N values are correct against live Linear before editing — don't trust the order `save_issue` was called; retrieve and confirm.
8. Platform / Cross-cutting V1.x issues (§7.1 entries marked as always-active substrate) that have already been promoted in a prior rotation stay in Linear. Do not re-promote them. Check the "Promoted to Linear at SELF-N" annotation before calling `save_issue`.

## Step 3 — update MILESTONES.md

9. Update MILESTONES.md "Recent activity" section:
   - Add a new 1-sentence entry at the top of the last-5 list: names the milestone that completed + headline count (e.g., "N Linear issues closed; PR #NN") + the PR number. ⚠ **Do not add a `Detail: [CHANGELOG vX.YY]` link** — `CHANGELOG.md` is frozen (see `WORKFLOW.md` § Artifact list) and no new version entries are written. The PR is the detail.
   - If the list is at 5 entries, drop the oldest.
   - 1 sentence only. Detail belongs in the PR body, which GitHub keeps.
10. ⚠ **REMOVED — do not write a `CHANGELOG.md` entry.** That file is frozen and unmaintained (see `WORKFLOW.md` § Artifact list); it went 19 versions stale without anyone noticing, because nothing reads it. The milestone-completion detail this step used to duplicate lives in the PR body. *(Step numbering kept so the surrounding references still resolve.)*
11. Land the doc update per the `/start-doc-update` → `/finish-doc-update` flow (per [ADR-009](../../../DECISIONS.md#adr-009) Decision 9).

## Linear MCP mechanics

- **`list_issues` with milestone filter** — verification gate; call before touching anything.
- **`list_milestones`** — read current/next milestone state before rotating. Do not assume sequence from memory.
- **`get_milestone`** — inspect specific milestone for its issue set + completion state.
- **`list_projects` / `list_teams`** — required context before calling `save_issue`; issue creation needs team + project assignment to land in the right workspace.
- **`save_issue`** — create promoted issues from BACKLOG.md §7 specs. Pass title + description (Source/AC verbatim) + team + project. Do NOT set `users_id` or tenant fields in the issue body — those are schema-layer fields, not Linear fields.
- **What NOT to do:** do not call `save_issue` for V1.0–V1.4 issues already in Linear. Do not bulk-load all BACKLOG.md §7 entries at once — current+next boundary is the hard discipline per ADR-017 Decision 2; over-promoting clutters the active workspace with unscheduled work.

## Failure modes / gotchas

| Failure | Catch |
|---|---|
| **Promoting before all issues are Done** | Step 0 `list_issues` gate — do not proceed if any issue is open. |
| **SELF-N assignment drift** | Read live SELF-N from `save_issue` response; do NOT infer from the last-known SELF-N in chat memory or from BACKLOG.md order. |
| **Over-promoting (bulk-loading future milestones)** | ADR-017 Decision 2 is explicit: current + next + Platform/Cross-cutting V1.x only. V1.5 promotes when V1.3 completes; V1.final promotes when V1.4 completes. |
| **V1.0–V1.4 carve-out violation** | The 89 existing issues (SELF-181→SELF-269) stay in Linear. Do not export, close, or re-import them on rotation. |
| **BACKLOG.md §7 count drift** | 18 entries staged 2026-06-03 (8 §7.1 + 10 §7.2). Verify live BACKLOG.md count before promoting — an edit since last read would change the set. |
| **Platform/Cross-cutting re-promotion** | §7.1 Architect substrate items (A1–A8) are "always active" per ADR-017 Decision 2; check "Promoted to Linear at SELF-N" annotation before `save_issue`. |
| **MILESTONES.md entry > 1 sentence** | Decision 1 is a hard compact-ledger constraint. Dense narrative goes in the PR body, never the ledger; violation re-inflates session-context bloat (the original ADR-017 context: 6000-word auto-loaded section across Waves 1–4). |
| **Skipping Sec consult on Sec joint-review entries** | §7 entries tagged "Sec joint-review mandatory" (e.g., A3, A5, A7, P10) require Security Reviewer consult before first implementation — not at promotion time per se, but flag them at issue-creation so they don't land in a sprint without the gate visible. |

## Notes

- This skill is **DevOps-owned** for the Linear workspace mechanics and repo-state update. Architect owns the migration ordering that gates whether a promoted issue's implementation can begin. The promotion itself (BACKLOG.md → Linear) does not unblock implementation — it puts the issue in the planning queue; actual unblocking happens when dependencies clear.
- The rehearsal target for this skill is **Phase 5 Step 7** (Linear MCP verification + workspace + milestone-rotation rehearsal per MILESTONES.md Phase 5 progress). At rehearsal time, no milestone has actually completed — the rehearsal exercises the read + verify steps (Steps 0, checks, BACKLOG.md read) without creating Linear issues. Actual issue creation waits for a real V1-SHIP gate.
- Composes with `/brief-drift-catch` (run Discipline 1 over any BACKLOG.md spec count or SELF-N range before forwarding to F/CTO ratify) and `/finish-doc-update` (to land the MILESTONES.md edits).
