# mosko-fintech

A personal fintech app run as a mini-business. The Founder/CTO is the human owner; the agent roster defined in `WORKFLOW.md` fills the other roles.

## Read first, every session

The project state-of-the-art lives in **`MILESTONES.md`** (compact state ledger; auto-loaded by the SessionStart hook per [ADR-009](DECISIONS.md#adr-009) Decision 6). The hook reads the head section (above `## Roadmap`) and injects it as session context — you don't need to manually open it.

Deeper context is **consult-on-demand** — read these only when the task requires them:

1. **`MILESTONES.md`** — compact state ledger; auto-loaded; current phase + step + active feature + recent activity. **Read first** (auto-load handles this).
2. **`WORKFLOW.md`** — project map: 10-phase structure (Phases 0 / 0.5 / 1–7) grouped under R/P/I+V outer categories per [ADR-009](DECISIONS.md#adr-009) Decision 2; agent roster; artifact list; operating model. Consult for "how do we operate" questions.
3. **`DECISIONS.md`** — architectural and product decisions with rationale. Hybrid format (consolidation pattern + terse pattern per [ADR-009](DECISIONS.md#adr-009) Decision 8). Consult for "why did we choose X" questions.
4. **`CHANGELOG.md`** — per-version PR-level execution history (extracted from WORKFLOW.md on 2026-05-23 per ADR-009 Decision 6). Consult for "when did X land?" / "what happened in v1.NN?" questions.
5. **`docs/PRD/index.html`** — product requirements (HTML; canonical post-PR-B). §1 vision / §2 V1 user stories (32 stories) / §3 success metrics / §6 out-of-scope / §7 constraints / appendices A/B/C. §4 / §5 / §8 stubs point to their relocated homes (rows 6 / 7 / 8). Consult for "what V1 should do" questions.
6. **`docs/SECURITY/index.html`** — V1 canonical Sec reference layer per [ADR-008](DECISIONS.md#adr-008) (received PRD §4 content in PR B). SD matrix + RT catalog + posture sub-§ (incl. V2-ship-gate Sec-consult inventory) — entry counts are read live from the doc, deliberately not pinned here (the pinned pair went stale by 11+16 entries before it was caught on 2026-08-25). Consult for security/compliance questions.
7. **`BACKLOG.md`** — two-purpose backlog: §5 V2+ deferred candidates (received PRD §5 content in PR B per [ADR-009](DECISIONS.md#adr-009) Decision 4) + §7 V1 staging queue (going-forward per [ADR-017](DECISIONS.md#adr-017) — repo-versioned V1 work-spec for milestones not currently in Linear; promotion at milestone-rotation). Consult for "what's deferred to V2?" or "what's queued for upcoming V1.X?" questions.
8. **`docs/MILESTONE-FRAMING.md`** — V1 sub-version convention + drop-replace migration pattern + Phase 4 handoff anchor (received PRD §8 content in PR B per [ADR-009](DECISIONS.md#adr-009) Decision 4). Conceptual spec distinct from `MILESTONES.md` live state ledger. Consult for milestone-shape / V1.x sub-version questions.
9. **`docs/ARCH/index.html`** — architecture HTML artifact (scaffolded in PR A; content drafted in Phase 3 by Architect). Consult for architecture detail post-Phase-3.
10. **`docs/archive/PRD-pre-html-migration.md`** — frozen Markdown snapshot of `PRD.md` at v1.30 (Phase 1 Step 3.5 closure), archived in PR B when content migrated to the HTML artifacts above. Read-only historical reference for any pre-PR-B cross-section refs.
11. **`docs/discovery-summary.md`** — the discovery conversation that produced WORKFLOW.md, captured as pivot points and principles. Background; not active context.

Per-directory `CLAUDE.md` files (e.g., `/api/CLAUDE.md`, `/supabase/CLAUDE.md`) provide scoped context when working inside those directories. They get created in Phase 5.

## Operating principles

- **Role separation matters.** When taking on a task, identify which agent role applies (see `WORKFLOW.md` → Agent Roster) and operate within that role's scope. Don't collapse multiple roles into one omniscient generalist — that defeats the synthetic-team friction the roster is designed to create.
- **Agents propose; the Founder/CTO disposes.** For non-trivial decisions, present 2–3 options with tradeoffs rather than picking one unilaterally. The human decides. For trivial decisions (formatting, naming, obvious right answers), just decide and execute.
- **Decisions get written down.** Anything non-obvious goes into `DECISIONS.md` as an ADR-style entry: what was chosen, what was considered, why. This is the message-to-future-self that prevents context loss across multi-week gaps.
- **Documents are the memory.** Each session starts fresh. The artifacts in this repo are how context survives between sessions. If something important isn't written down, it's effectively lost.

## Backlog and task tracking

Project work is tracked in **Linear**, organized as initiatives → projects → issues. Linear MCP activated in Phase 4 Step 2. **There is no `TASKS.md` artifact** — Linear is the single source of truth for what's actively being worked on.

**Linear scope per [ADR-017](DECISIONS.md#adr-017) Decision 2:** Linear holds the **current milestone + next milestone only** (plus Platform / Cross-cutting V1.x always). All other planned milestones live in `BACKLOG.md` §7 with full Source / AC / Dependencies specs. Promotion to Linear happens at milestone-rotation (when current completes; next becomes current; what-was-after-next promotes from BACKLOG.md → Linear). Going-forward from Wave 6 (V1.5); existing V1.0–V1.4 Linear issues stay in place.

## Repo conventions

- All artifacts live in this repo. Source of truth is the repo, not local files or chat history.
- Migrations live in code, not in the Supabase dashboard.
- Secrets never go in the repo. Use `.env` files (gitignored) and Coolify environment variables.
- Branch protection on `main`. Merges via PR with passing CI.
- Commit messages reference the version bump or Linear issue when applicable.

## Current state

To find out what phase the project is in, what's locked, and what's next: read `MILESTONES.md` head (auto-loaded by the SessionStart hook; the section above `## Roadmap`). Historical per-version PR narrative lives in `CHANGELOG.md` (consult on demand).

## HTML doc artifact set (post-PR-B)

PR A landed the scaffolding; **PR B landed the content migration** per [ADR-009](DECISIONS.md#adr-009) Decisions 3 + 4 + 5. `PRD.md` is archived; HTML artifacts are canonical.

The doc files themselves are described in the "Read first" list above (rows 5–8 and 10). Supporting assets:

- `docs/_assets/style.css` — shared styling (incl. CSS class taxonomy per Decision 5).
- `docs/_assets/mermaid.min.js` — vendored Mermaid runtime (no CDN; per Decision 5 sub-decision 3).
- `docs/_assets/mermaid-init.js` — vendored-load initializer.

## When in doubt

If unsure which agent role applies to a request, **default to team-lead behavior** (per [ADR-009 Decision 1](DECISIONS.md#adr-009) — CoS role absorbed into the main session as team-lead). **The role is defined in `.claude/roles/team-lead.md`** — read it there; it is deliberately not restated here, so there is one place to change it.

It sits in `roles/` rather than `agents/` because team-lead **is** the main session and must not become spawnable: every `.md` under `.claude/agents/` becomes a `subagent_type`. A `SessionStart` hook loads it at the start of every session, so this pointer is for humans — the session already has the content.

# Response

Default to terse. Skip the reasoning tour and Stream of Conciousness preambles.

- Starting work on an Item:
  - Always provide an Executive Summary to F/CTO on What / Why / How for implementing the Item Task
  - Ensure that each team-member starts work in its own workspace. Everyone is on a common git / github branch for the same Issue.
- During work on an Item:
  - Always wait to collect data from all team-members before giving an update summary. Don't comment inline as messages come back from team-members
  - Make trivial decisions on my behalf up to the PR review
- End of work on an Item:
  - Ensure that all team-members are complete and idle first
  - Generate and provide an Executive Summary that shows What was decided, what was done, and the whys for the decision making
  - Prompt for a review by F/CTO, or by any agent authorized to perform a PR review.
- Merging PR to main:
  - Make sure that remote branches that were used are cleared
  - Provide a list of Items on deck and short descriptions of what they are
  - Provide a recommendation of what to work on next and why
