# Claude Code Handoff Prompts

Manual handoff prompts for starting Claude Code sessions on the mosko-fintech repo.

**Note on the auto-load model** (per [ADR-009](../DECISIONS.md#adr-009) Decision 6):

The SessionStart hook in `.claude/settings.json` **automatically** loads the orient context from `MILESTONES.md` head at the start of every session. Routine re-orientation is handled by the hook; the prompts in this file are manual fallbacks for cases the hook doesn't cover (first-session bootstrap, phase transitions).

---

## First session — context handoff from planning Chat Project

Paste this into Claude Code the first time you run `claude` in the mosko-fintech repo:

> I'm starting Claude Code on this repo for the first time. The project context lives in `MILESTONES.md` (compact state ledger; auto-loaded by the SessionStart hook), with `CLAUDE.md` at the repo root pointing at the orientation docs. Please read both now.
>
> Background you should know: Phase 0 (Discovery & Operating Model) was completed in a separate Chat Project. That conversation produced WORKFLOW.md as the founding artifact for the project. WORKFLOW.md is currently at v1.31+. All decisions made during discovery are captured in the document — there is no separate conversation log to consult.
>
> The current phase is captured in MILESTONES.md's "Current Phase" block. The agent roster lock is in [ADR-009](../DECISIONS.md#adr-009) Decision 1 — the main session acts as **team-lead** (Chief of Staff was dropped during the template-adoption brainstorm).
>
> Before doing anything else, please:
> 1. Confirm you have read `CLAUDE.md` and the MILESTONES.md head (auto-loaded by the hook).
> 2. Summarize, in your own words, what mosko-fintech is and what role you're playing.
> 3. State what phase the project is in and what the immediate next deliverable is.
> 4. Flag any apparent inconsistencies or open questions in the documents that I should resolve before we proceed.
>
> Do not start drafting until I confirm we're aligned.

**Why this prompt is shaped the way it is:**

- It points at `MILESTONES.md` as the primary state-of-the-art source (the auto-load anchor).
- It supplies background that isn't in the docs (the existence of a prior Chat Project) without trying to import its conversation — the documents are the memory.
- It explicitly assigns a role per the post-ADR-009 roster (team-lead, not Chief of Staff).
- The four-step verification forces Claude Code to *demonstrate* it has the orientation, rather than nodding along.
- The "do not start drafting" instruction prevents jumping into execution mode prematurely.

---

## Subsequent sessions — usually handled automatically by the SessionStart hook

The SessionStart hook in `.claude/settings.json` auto-loads `MILESTONES.md` head and embeds the re-orient instructions. Most sessions don't need a manual prompt.

**Manual fallback** (paste only if the hook didn't fire — e.g., stale worktree from before the hook landed, or `.claude/settings.json` is missing):

> Re-orienting on mosko-fintech. From `main` at the project root:
>
> 1. Read `MILESTONES.md` head (everything above `## Roadmap`). This is the compact state ledger; auto-load anchor per [ADR-009](../DECISIONS.md#adr-009) Decision 6.
> 2. Cross-check against main: `git worktree list` + `git log --all --not main --oneline` + `git status`.
> 3. Summarize in 4–6 lines: current phase + step, active feature (if any), recent activity, immediate next deliverable. Surface any unmerged-branch deltas as a separate "discrepancies" list — don't fold them into the main-anchored summary (per memory `feedback_main_anchored_orient`).
> 4. Consult on demand only — `WORKFLOW.md`, `DECISIONS.md`, `CHANGELOG.md`, `docs/PRD/`, `docs/ARCH/`, `docs/SECURITY/` should NOT be auto-read unless the user's question requires them.

**Why this is a fallback rather than the primary path**: the hook already embeds these instructions in `additionalContext` at session start. Pasting them manually duplicates what the hook does. The fallback exists because the hook can fail to fire (worktree freshness gotcha; missing `.claude/settings.json`; new clone).

---

## Phase-transition prompt

When you complete a phase and are about to enter the next one, use this:

> We just completed Phase [N]. Before we enter Phase [N+1]:
>
> 1. Update `WORKFLOW.md`: mark Phase [N] status as complete, add a "Lessons learned" subsection capturing what worked and what didn't, bump the version, add an entry to `CHANGELOG.md` (per [ADR-009](../DECISIONS.md#adr-009) Decision 6 — execution log lives there now, not in WORKFLOW.md).
> 2. Flesh out Phase [N+1]'s "Detailed steps" subsection just-in-time, since we're about to enter it.
> 3. Verify `WORKFLOW.md`'s open-questions list — close anything Phase [N] resolved, add anything new that surfaced.
> 4. Update the header's "Current phase" pointer in `WORKFLOW.md`, AND update `MILESTONES.md`'s "Current Phase" block to match (so the next session's auto-load reflects reality).
> 5. If the phase produced new ADRs or substantive locks, log them in `DECISIONS.md` (consolidation pattern for canonical-reference work; terse pattern for one-off decisions; per ADR-009 Decision 8 hybrid policy).
>
> Show me the proposed updates as a single diff before committing.

**Why this version**: Phase transitions are the highest-leverage moment for capturing lessons learned, and the easiest moment to forget. The diff-before-commit step gives you a chance to review. The split between WORKFLOW.md's "Current phase" header and MILESTONES.md's "Current Phase" block is intentional — WORKFLOW is the stable map (rarely touched); MILESTONES is the live ledger (touched at every state change).

---

## A note on iterating these prompts

These are starting points, not final templates. After your Claude Code sessions, you'll notice things — orient summary getting cursory, role-statement drifting, the four-step verification getting skipped. When that happens, refine the prompts (and the SessionStart hook in `.claude/settings.json` for routine cases) and commit them to the repo. The prompts themselves become an artifact that improves over time, just like everything else in the project.
