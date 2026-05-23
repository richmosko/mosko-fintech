# mosko-fintech

A personal fintech app run as a mini-business. The Founder/CTO is the human owner; the agent roster defined in `WORKFLOW.md` fills the other roles.

## Read first, every session

These documents are the project's source of truth. Read them in order before taking on any task:

1. **`WORKFLOW.md`** — project map and execution log. Contains the eight-phase structure, agent roster, artifact list, current phase, and operating model. The header tells you which phase the project is currently in.
2. **`DECISIONS.md`** — architectural and product decisions with rationale (when it exists; created in Phase 0.5 or Phase 1).
3. **`PRD.md`** — product requirements (when it exists; created in Phase 1).
4. **`ARCHITECTURE.md`** — system design (when it exists; created in Phase 3).
5. **`docs/discovery-summary.md`** — the discovery conversation that produced WORKFLOW.md, captured as pivot points and principles. Background reading; not active context.

Per-directory `CLAUDE.md` files (e.g., `/api/CLAUDE.md`, `/supabase/CLAUDE.md`) provide scoped context when working inside those directories. They get created in Phase 5.

## Operating principles

- **Role separation matters.** When taking on a task, identify which agent role applies (see `WORKFLOW.md` → Agent Roster) and operate within that role's scope. Don't collapse multiple roles into one omniscient generalist — that defeats the synthetic-team friction the roster is designed to create.
- **Agents propose; the Founder/CTO disposes.** For non-trivial decisions, present 2–3 options with tradeoffs rather than picking one unilaterally. The human decides. For trivial decisions (formatting, naming, obvious right answers), just decide and execute.
- **Decisions get written down.** Anything non-obvious goes into `DECISIONS.md` as an ADR-style entry: what was chosen, what was considered, why. This is the message-to-future-self that prevents context loss across multi-week gaps.
- **Documents are the memory.** Each session starts fresh. The artifacts in this repo are how context survives between sessions. If something important isn't written down, it's effectively lost.

## Backlog and task tracking

Project work is tracked in **Linear**, organized as initiatives → projects → issues. Linear MCP integration is set up in Phase 5; until then, planning happens in this repo's markdown documents. **There is no `TASKS.md` artifact** — Linear is the single source of truth for what's being worked on.

## Repo conventions

- All artifacts live in this repo. Source of truth is the repo, not local files or chat history.
- Migrations live in code, not in the Supabase dashboard.
- Secrets never go in the repo. Use `.env` files (gitignored) and Coolify environment variables.
- Branch protection on `main`. Merges via PR with passing CI.
- Commit messages reference the version bump or Linear issue when applicable.

## Current state

To find out what phase the project is in, what's locked, and what's next: read the header and changelog of `WORKFLOW.md`.

## In-flight: HTML doc conversion (scaffolded; content migration pending)

PR A landed the scaffolding for `docs/PRD/`, `docs/ARCH/`, `docs/SECURITY/`, `docs/_assets/` per [ADR-009](DECISIONS.md#adr-009) (Decisions 3+4+5). These directories contain placeholder `index.html` files showing the locked conventions; **content migration is PR B** (still pending). `PRD.md` remains the live source of truth until PR B lands.

- `docs/PRD/index.html` — mosko §1–§8 schema; §4/§5/§8 marked for relocation per Decision 4.
- `docs/SECURITY/index.html` — receives migrated PRD §4 in PR B (V1 Sec canonical reference per ADR-008).
- `docs/ARCH/index.html` — content drafted in Phase 3 by Architect.
- `docs/_assets/style.css` — shared styling.
- `docs/_assets/mermaid.min.js` — vendored Mermaid runtime (no CDN; per Decision 5 sub-decision 3).
- `docs/_assets/mermaid-init.js` — vendored-load initializer.

After PR B + PR C land, the reading-order block above will narrow to a compact-ledger auto-load model per [ADR-009 Decision 6](DECISIONS.md#adr-009) (MILESTONES.md anchor; everything else consult-on-demand).

## When in doubt

If unsure which agent role applies to a request, **default to team-lead behavior** (per [ADR-009 Decision 1](DECISIONS.md#adr-009) — CoS role absorbed into the main session as team-lead): orchestrate, ask which role the human wants to invoke, or escalate. Don't execute as a generic assistant — that's the role-collapse failure mode.
