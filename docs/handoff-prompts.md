# Claude Code Handoff Prompts

Copy-paste prompts for starting Claude Code sessions on the mosko-fintech repo. Two versions: one for the very first session (when porting context from the planning Chat Project), and a shorter one for routine subsequent sessions.

---

## First session — context handoff from planning Chat Project

Paste this into Claude Code the first time you run `claude` in the mosko-fintech repo:

> I'm starting Claude Code on this repo for the first time. The project context lives in `WORKFLOW.md`, with `CLAUDE.md` at the repo root pointing at the orientation docs. Please read both now.
>
> Background you should know: Phase 0 (Discovery & Operating Model) was completed in a separate Chat Project. That conversation produced WORKFLOW.md as the founding artifact for the project. WORKFLOW.md is currently at v0.5. All decisions made during discovery are captured in the document — there is no separate conversation log to consult.
>
> The next phase is **Phase 0.5 — Agent Roster Definition**, which we'll work on here. That phase produces six agent definition files in `/agents/` for the roles active in Phases 1–4 (Chief of Staff, Product Manager, Architect, Security Reviewer, UX Designer, Visual Designer). The remaining four agent roles (Backend Engineer, Frontend Engineer, QA, DevOps) get defined later in Phase 5.
>
> For this session and through Phase 0.5, you are operating as **Chief of Staff**. That is the role I have been working with throughout planning. Chief of Staff orchestrates, maintains WORKFLOW.md, and ensures phase transitions are clean — it does not execute on the build itself.
>
> Before doing anything else, please:
> 1. Confirm you have read `CLAUDE.md` and `WORKFLOW.md`.
> 2. Summarize, in your own words, what mosko-fintech is and what role you're playing.
> 3. State what phase the project is in and what the immediate next deliverable is.
> 4. Flag any apparent inconsistencies or open questions in the documents that I should resolve before we proceed.
>
> Do not start drafting agent files yet. We'll plan the Phase 0.5 detailed steps together first.

**Why this prompt is shaped the way it is:**

- It explicitly names the orientation docs to read, so Claude Code doesn't guess.
- It supplies background that isn't in the docs (the existence of a prior Chat Project) without trying to import its conversation — the documents are the memory.
- It explicitly assigns a role, because role assignment was a recurring theme during discovery and shouldn't dissolve at the surface boundary.
- The four-step verification at the bottom forces Claude Code to *demonstrate* it has the orientation, rather than nodding along. If the summary or role-statement is wrong, you'll catch it before any work starts.
- The "do not start drafting" instruction prevents a common Claude Code pattern of immediately jumping into execution mode when the documents look executable.

---

## Subsequent sessions — short re-orientation

For sessions after the first, paste this:

> Re-orienting on mosko-fintech. Please re-read `CLAUDE.md` and `WORKFLOW.md`, then summarize: (1) what phase the project is in, (2) what role you're playing in this session, (3) what the immediate next deliverable is, and (4) anything that's changed in the workflow document's changelog since you'd expect to last have seen it.
>
> If there's an active feature branch, also check git status and tell me where things stand on it.

**Why this version:** Claude Code starts fresh each session, but the artifacts have grown. The four-step summary makes Claude Code re-derive its orientation from the current state of the repo, rather than assuming nothing has changed. The git status line catches "I left a branch half-done" situations after a multi-week gap.

---

## Phase-transition prompt

When you complete a phase and are about to enter the next one, use this:

> We just completed Phase [N]. Before we enter Phase [N+1]:
>
> 1. Update `WORKFLOW.md`: mark Phase [N] status as complete, add a "Lessons learned" subsection capturing what worked and what didn't, bump the version, add a changelog entry.
> 2. Flesh out Phase [N+1]'s "Detailed steps" subsection just-in-time, since we're about to enter it.
> 3. Verify `WORKFLOW.md`'s open-questions list — close anything Phase [N] resolved, add anything new that surfaced.
> 4. Update the header's "Current phase" pointer.
>
> Show me the proposed updates as a single diff before committing.

**Why this version:** Phase transitions are the highest-leverage moment for capturing lessons learned, and the easiest moment to forget. Forcing the workflow update before entering the next phase preserves the "documents are the memory" principle. The diff-before-commit step gives you a chance to review.

---

## A note on iterating these prompts

These are starting points, not final templates. After your first few Claude Code sessions, you'll notice things — Chief of Staff role drifting, the four-step verification getting skipped, document-reading getting cursory. When that happens, refine the prompts and commit them to the repo (e.g., as `docs/handoff-prompts.md`, the file you're reading now). The prompts themselves become an artifact that improves over time, just like everything else in the project.
