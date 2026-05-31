# WORKFLOW.md

**Project:** mosko-fintech
**Current version:** v1.42
**Last updated:** 2026-05-31
**Current phase:** **Phase 2 (UX & Design) + Phase 3 (Technical Architecture) — entered in parallel 2026-05-27 per [ADR-012](DECISIONS.md#adr-012).** Phase 1 (Product Definition / PRD) closed 2026-05-26 with all 16 substantive architectural locks ratified + candidate P3 disposed + Lock 9 amended (see [ADR-011](DECISIONS.md#adr-011)); close-work merged across 5 stacked PRs (#51 ADR-011 + #56 §SECURITY tables + #53 §SECURITY annotations + #54 PRD §7.3 + #55 BACKLOG/WORKFLOW/MILESTONES). Phase 2 + Phase 3 input surfaces are independent (PRD §2 + ADR-011 + locks log give both phases fully-specified inputs); coupling touchpoint was Architect's frontend framework choice ↔ Visual Designer's design tokens format — **RESOLVED 2026-05-29 via [ADR-015](DECISIONS.md#adr-015)** (SvelteKit + no Tailwind; `docs/DESIGN/tokens.css` consumed natively via Svelte component-scoped CSS). **Phase 2 Steps 1–10 complete 2026-05-29** (ADR-013 / ADR-014 / ADR-015 trio); Phase 2 ready to close pending Phase 3 exit per ADR-012 joint-close. Both phases close together at Phase 4 (Project Scoping) entry gate; **WORKFLOW.md header pointer stays here until both close** per ADR-012. Architect Phase 3 consumes ADR-011 + locks log (gitignored at `temp/step-4-locks-log.md`) + 13 Phase 3 carry-over tasks; in flight: ARCH system overview (PR #60), RT-26 / §4.2 V1-web-app `SUPABASE_SERVICE_ROLE_KEY` fence (PR #62), ADR-015 framework lock (PR #63), ARCH §4 + §4.1 Tech Stack table + RT-26 file-glob allowlist anchor (PR #65), ARCH §4 Auth row (PR #66), ARCH §3 Data Flow + §3.1 Plaid webhook + §3.2 PDF render cross-container sequenceDiagrams + F11 SECURITY forward-cross-refs (PR #67), ARCH §4 Observability row + conditional-lock + named-fallback (new project convention) + F1 V1-SHIP-BLOCK Phase 5 gate + F2 pull-based detection + F3/F9 RT-21 audit-log + F10 §4.6 inventory (v) (PR #68), ARCH §5 Deployment Topology + operational/admin trust boundaries + inter-container network isolation Phase 5 + canonical-territory-respect section-hint pattern + first cross-PR composition test of v1.40 conditional-lock convention (PR #69), ARCH §7 Integration Points + §7.1 Plaid endpoint posture + ADR-016 RT-26 three-entry allowlist enumeration + section-hint convention second application + §10 attribution discipline 6th consecutive surface CLEAN + verbatim-vs-paraphrase Architect self-catch (PR #70 `phase/plan-arch-7-integration-points`). UX + Visual Designer lead Phase 2 from PRD §2's 32 V1 user stories. See [MILESTONES.md](MILESTONES.md) for live current-phase state. Phase 1 historical narrative at [CHANGELOG.md](CHANGELOG.md) v1.18 → v1.31 (Step 2 ratification + Step 3 PRD drafting + Step 3.5 editorial rewrite + post-rewrite verify pass); Step 4 architectural drilling at v1.32; phase-transition PR at v1.33; Phase 2 Steps 1–3 + ADR-013 at v1.34; Phase 2 Steps 4–9 + ADR-014 at v1.35; post-ADR-015 state-refresh at v1.36; ARCH §4 + §4.1 Tech Stack + RT-26 allowlist anchor at v1.37; ARCH §4 Auth row + lessons-learned at v1.38; ARCH §3 Data Flow + §3.1/§3.2 cross-container flows + Phase 5 PDF-JWT mechanism deferral at v1.39; ARCH §4 Observability row + conditional-lock + named-fallback pattern at v1.40; ARCH §5 Deployment Topology + canonical-territory-respect section-hint + first cross-PR composition test of v1.40 convention at v1.41; ARCH §7 Integration Points + ADR-016 RT-26 allowlist three-entry enumeration + section-hint convention second-application durability + verbatim-vs-paraphrase Architect self-catch at v1.42.

---

## Changelog

Per-version execution narrative lives at [`CHANGELOG.md`](CHANGELOG.md) at repo root. Append-only; newest at top. Consult on demand when answering "when did X land?" questions.

Extracted from this file on 2026-05-23 per [ADR-009](DECISIONS.md#adr-009) Decision 6 (~1278 lines moved; was ~71% of WORKFLOW.md). 39 version entries (v0.1 → v1.33).

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

## Doc review loop (`comments.md` sidecar)

Each HTML doc (`PRD`, `ARCH`, `SECURITY`) supports an optional sidecar `docs/<DOC>/comments.md` for in-process review notes. It's a feedback loop with Claude: write per-section comments in the file, then run `/refine-doc` to have the relevant lead address them. Adopted from `richmosko/project_template` per [ADR-010](DECISIONS.md#adr-010) (selective-adoption framework set up by [ADR-009](DECISIONS.md#adr-009) Decision 8).

### Format

```markdown
# PRD Comments

Working notes for review of `docs/PRD/index.html`. Comments are removed when
`/refine-doc` addresses them.

---

## §sec-1

The vision paragraph reads as too solo-focused — pull forward the
"replaces existing spreadsheet workflow" framing from Appendix A.

## §sec-6

Should "mobile-native app" stay as a permanent non-goal, or be re-classified
as V2+ trajectory? See ADR-002 §3.0 — feels worth re-examining.
```

Each `## §<section-id>` anchor matches a `<section id="...">` in the corresponding HTML doc. Section IDs already exist on every section in mosko's PRD (`sec-overview`, `sec-1` … `sec-8`, `appendix-a` … `appendix-c`) and `docs/SECURITY/index.html` — no markup changes needed.

### Workflow

```
1. Open docs/<DOC>/index.html in browser (file:// or via a doc-serve mechanism).
2. Read; jot per-section feedback into docs/<DOC>/comments.md.
3. /start-doc-update <doc>-address-review-comments    # branch
4. /refine-doc <DOC>                                  # lead addresses comments
5. Review the diff to docs/<DOC>/index.html.
6. /finish-doc-update                                 # opens PR
7. Merge via GitHub UI or `gh pr merge --squash <pr#>`
```

`/refine-doc` walks the sidecar in file order, addresses each comment in the matching HTML section, and **removes the addressed comments** from `comments.md` as it goes. Comments that need Founder/CTO clarification stay in place with a `> [refine-doc deferred YYYY-MM-DD]: <reason>` annotation — answer the question, re-run the skill.

### Gitignored, by design

`docs/*/comments.md` is gitignored. Comments are working notes, not permanent record:

- The **resolution** is the doc change itself (committed via PR).
- If a comment leads to a decision worth preserving long-term, log it in [`DECISIONS.md`](DECISIONS.md) before running `/refine-doc` — once addressed, the sidecar entry is gone.
- Keeps PR history clean (no review-noise commits).

### When to use

- **PRD review** during Phase 1 Step 4 (Architect's PRD ratification consult) — primary near-term use case. Walk through `docs/PRD/index.html` in the browser, jot feedback by section, refine.
- **ARCH / SECURITY review** during Phase 3 (Plan outer category) — same loop, different doc.
- **Periodic refreshes** mid-project — when a milestone closes, take a pass at whether the PRD assumptions still hold; same loop.

### Inline-authoring mode (`/serve-docs` or `scripts/serve-docs.sh`)

Hand-editing `comments.md` works in any editor, anywhere. For a friendlier review experience, the repo ships a local Python server + JS widget that lets you author comments inline while reading the doc in a browser.

**Two ways to start it:**

```
/serve-docs PRD              # preferred — server runs in background under
                             # the Claude session; cleaned up on /exit;
                             # opens the browser to PRD
                             # (omit the doc arg to just start the server)
```

```bash
./scripts/serve-docs.sh      # direct invocation — runs in your terminal
                             # with live request logs; useful for debugging
                             # the server itself
```

Both run the same server (Python stdlib only) at `http://localhost:8765` and serve `docs/`. The `/serve-docs` skill probes for an already-running instance before launching, so it's safe to invoke repeatedly. Browse to `http://localhost:8765/PRD/` (or `ARCH/`, `SECURITY/`) — the widget activates:

- **A small status badge** in the bottom-right shows `connected (N comments)` or `offline`.
- **Hover any section heading** to reveal a `+ Comment` button.
- **Click `+ Comment`** to open an inline panel under the heading: any existing comments for the section are listed (read-only), and a textarea + Save button let you add a new one.
- **Cmd/Ctrl+Enter** saves; **Esc** cancels.
- **Save POSTs to the server**, which appends a `## §<section-id>` block to `docs/<DOC>/comments.md` on disk. The widget refreshes inline.

Sections that already have comments show a `💬 N` count badge next to the heading. Click the badge to open the panel showing existing comments.

**Format compatibility:** the widget and `/refine-doc` use the **same** `comments.md` format. You can mix authoring methods freely — write some comments via the widget, others by hand-editing the file. Both feed `/refine-doc` identically.

**Graceful degradation:** if you open the HTML doc directly from disk (`file://`), or via a non-localhost host, the widget recognizes it can't reach a local server and shows the status badge as offline with a hint. The doc remains fully readable; only comment authoring is disabled. Hand-editing `comments.md` still works.

**Lifecycle:** when launched via `/serve-docs`, the server is bound to the Claude session and dies on `/exit`. When launched directly from a terminal, Cmd+C (Ctrl+C) to stop. Override the port with `DOCS_PORT=8080 ./scripts/serve-docs.sh` if 8765 collides.

**Security shape:** the server binds to `127.0.0.1` only (no LAN exposure), accepts only its two API endpoints (`GET /api/comments`, `POST /api/comments`), and writes only to `docs/<DOC>/comments.md` after validating `doc` against a whitelist (`PRD`, `ARCH`, `SECURITY`) and `section` against the `[a-z][a-z0-9-]*` pattern. No auth needed.

### Pass status

- **Pass 1** (shipped at ADR-010 PR 1) — convention + `/refine-doc` skill. Hand-edit `comments.md`, run the skill.
- **Pass 2** (shipped at ADR-010 PR 2) — inline browser widget + local Python server + `/serve-docs` skill. Same on-disk format; nicer authoring UX. Widget POSTs new comments to `docs/<DOC>/comments.md` while you read the doc in a browser; both authoring paths feed `/refine-doc` identically.
- **Pass 3** (not planned) — would handle inline edit/delete of existing comments via the widget, comment threading, or multi-user attribution. Defer until single-user usage surfaces a real need.

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

**Status:** ✅ Complete (2026-05-26) — Step 4 drilling complete; close-work landed across 5 stacked PRs (#51 ADR-011 + #56 §SECURITY tables + #53 §SECURITY annotations + #54 PRD §7.3 + #55 BACKLOG/WORKFLOW/MILESTONES). See [MILESTONES.md](MILESTONES.md) for current-phase live state.

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

**Lessons learned (Phase 1 Step 4 architectural drilling cycle, 2026-05-25 → 2026-05-26):**

The active drilling cycle ratified 16 architectural locks + 4 cross-cutting project-convention meta-patterns + candidate P3 disposition under the Architect-lead + Sec-joint-review + F/CTO-ratification pattern locked at ADR-003. The cycle produced [ADR-011](DECISIONS.md#adr-011) as the canonical-reference layer for Phase 3 consumption. Key cross-phase lessons:

- **Sec joint-review surfaced 8 chain-attack catches that Architect's drills missed.** Across the joint-flag reviews (Flags #4 / #5 / #6 / #7 / #8 / #9 / #13), Sec consistently caught attack surfaces Architect's options-drill didn't anticipate: cross-tenant link attacks via FK enforcement (4 instances of the §8 meta-pattern); chain attacks via parent `users_id` mutation orphaning child rows (Lock 12 mod #2 catch); infrastructure-credential-presence future-regression fence (Lock 13 mod #2 catch); app-layer mass-assignment + numeric adversarial battery at user-facing surfaces (Lock 14 catch); schema-level orthogonality awareness when retroactively-locked schema decisions cascade (Lock 15 catch on Lock 9). **Implication for Phase 3 + Phase 6:** Sec joint-review is load-bearing on any surface touching auth / privileged-context / multi-layer-fence territory; the chain-attack catches were systematic, not one-off.

- **4 project-convention meta-patterns emerged from the lock-set sequence** — captured as ADR-011 Decisions 1-4: §6 privileged-context-write discipline; §7 immutable INSERT-new-version for audit-class surfaces; §8 cross-tenant FK-bypass family + matched-tenant validation; §10 defense-in-depth fencing across surface boundaries + schema-level orthogonality awareness. **Implication for Phase 3 + Phase 5:** new surfaces in those classes evaluate against the established conventions at design time rather than rediscovering them; the conventions are project-canonical now.

- **Synthetic-team subagent dynamics are stable but require routing discipline.** Architect + Sec teammates in team mode (per ADR-003) maintained persistent context across the cycle. **Sync-mismatch pattern observed three times** — Architect produced v1.1 "enrichment" cycles after F/CTO ratification, interpreting Sec routing briefs (sent post-ratify to Sec) as additional Architect direction. Recovery via explicit anchor message naming the misattribution + commit to `to: "architect"` routing convention for any genuine Architect direction. **Implication for future team-mode sessions:** route briefs explicitly with audience-disambiguation when stacking ratification + downstream consult; pacing conventions per `feedback_one_question_at_a_time` + `feedback_pm_sync_mismatch_pattern` remain load-bearing.

- **F/CTO clarification interventions were materially load-bearing on three locks.** Flag #11 cost-feasibility v1 → v1.1 reframe (corrected miscategorization of FMP + Plaid as feature-scaling when both are fixed-cost; reframed VPS as the actual feature-driver with Hetzner cax21 as incumbent baseline); Lock 14 mod #9 amendment (Sec addendum on `updated_at` UPDATE-refresh trigger); Lock 15 amend (3 Sec addendum mods including server-derived-only fence + audit-log shape extension). **Implication:** F/CTO substantive review of Architect drills + Sec verdicts surfaces material framing issues; pacing ratify gates per `feedback_late_phase_density_overload` produces better outcomes than rubber-stamping.

- **Locks log + ADR-011 separation works well at this scale.** Per-lock bullet-level rationale + full Sec-mod inventory lives at `temp/step-4-locks-log.md` (gitignored authoritative state file; ~1200 lines); ADR-011 captures the decision-grade content at Phase 3 consumption granularity (~500 lines). Two-tier persistence — working file in `temp/` + committed canonical-reference ADR — matches the `feedback_working_artifacts_temp_not_docs` + `feedback_brainstorm_logging` conventions established earlier in Phase 1. **Implication for Phase 3+:** ARCH drafting will consume ADR-011 + locks log; locks log remains gitignored, archived as historical reference.

- **The 4-PR close-work decomposition (ADR-011 + §SECURITY tables + §SECURITY annotations + meta-docs) per `feedback_late_phase_density_overload`** produces independently-reviewable PRs over a single mega-PR. PR review cost is lower per-PR; stacked-PR dependency graph (PR #51 → #52 → #53 → #54) renders cleanly on GitHub. **Implication for future close-cycles:** decompose by artifact-class + reviewer-cognitive-load rather than commit-by-commit; stack PRs on GitHub when downstream PRs reference upstream content.

- **Candidate P-flags (P1 / P2 / P3) successfully resolved disposition for incumbent-exceeds-V1 surfaces.** The `feedback_incumbent_exceeds_v1_review` guardrail established at Flag P2 (Lock 2) operationalized at Lock 6 (P1 `users_id` rename, Architect-led), Lock 2 (P2 `account_users`-as-V1-dormant, PM-led), and Lock 16 (P3 stock-screening V1-default, F/CTO direct disposition). **Implication for future incumbent surfaces:** the guardrail is project-canonical; do NOT auto-accept incumbent-exceeds-V1 via "selective adoption" framing.

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

**Status:** 🟡 In progress (Steps 1–10 complete; ready to close pending Phase 3 exit per [ADR-012](DECISIONS.md#adr-012) joint-close). Entered in parallel with Phase 3 per [ADR-012](DECISIONS.md#adr-012). UX Designer + Visual Designer co-lead; consumes [PRD §2](docs/PRD/index.html#sec-2) 32 V1 user stories. **Steps 1–3 complete (2026-05-28):** all 6 user-story clusters drilled into flow documents + PM-traceability-PASSed; full 2-sitting F/CTO walk-through signed off; 6 parked decisions (P1–P6) + the D1 staleness principle decided and consolidated in [ADR-013](DECISIONS.md#adr-013). **Steps 4–9 complete (2026-05-29):** wireframes (low-fi HTML) → UX→Visual handoff (~45 screens + INV-3 components) → palette/typography/dark-mode checkpoint → full design-system spec applied across all 6 clusters → two-tier token taxonomy. Design foundation + system locked in [ADR-014](DECISIONS.md#adr-014) (Palette B refined · barely-cool canvas + pure-white cards · Inter+JetBrains Hybrid · Canary-Yellow `#FFEF00` attention · dark plan-for · primitive→semantic token tiers). **Committed home established: [`docs/DESIGN/`](docs/DESIGN/)** (design system + flows + wireframes) — resolves the ADR-013 flow-artifact-home follow-up. **Step 10 (tokens-as-code) CLOSES by composition (2026-05-29) via [ADR-015](DECISIONS.md#adr-015)** — SvelteKit + no Tailwind locks the framework; `docs/DESIGN/tokens.css` IS the consumption format, imported globally in `src/app.css`; Svelte component `<style>` blocks use `var(--c-*)` natively (no transformation layer, no intermediate format). Framework-coupling touchpoint per [ADR-012](DECISIONS.md#adr-012) RESOLVED. Phase-3 ARCH handoffs (A1–A4, H1–H2, RT-13-tracks-D1, §2.6 injection invariants) in ADR-013 Consequences.

**Detailed steps:**

1. **Session prerequisites and team setup (UX + Visual + Founder/CTO).** Before kicking off Phase 2 work, **restart Claude Code** so the `ux-designer` and `visual-designer` subagents from `.claude/agents/*.md` are loaded into the session's registry. Phase 2 runs in **team mode** per [ADR-003](DECISIONS.md#adr-003) and `feedback_team_mode_default` — spawn teammates via `Agent(team_name="phase-2-ux-design", subagent_type=..., name=...)`; plain `Agent` calls without `team_name` fall back to task-mode and lose persistent context. Mandatory pre-reading for the session: `docs/PRD/index.html` (especially §2 V1 user stories — all six clusters — and §7.3 single-user V1 + multi-tenant forward-compat constraint), `WORKFLOW.md` Phase 2 scaffold, the two phase-2 agent files (`.claude/agents/ux-designer.md`, `.claude/agents/visual-designer.md`), and `MILESTONES.md` head. Confirm the **Phase 3 Architect team is also up and reachable via cross-team handoff** — Phase 2 runs parallel with Phase 3 per [ADR-012](DECISIONS.md#adr-012); the frontend-framework choice (Architect's Phase 3 deliverable) is the coupling point for Visual's design-token format (see step 5).

2. **Flow drafting per user-story cluster (UX-lead, PM-consult on traceability).** UX drills the six PRD §2 user-story clusters in **dependency order**, not PRD order: §2.4 cross-cutting (account onboarding / manual entry / re-auth) **first** — it is the foundation surface without which net worth, allocation, and spending surfaces have no data — then §2.1 net worth → §2.2 asset allocation → §2.3 spending and income categorization → §2.5 estimated taxes → §2.6 monthly report. For each cluster, UX produces a structured flow document covering: screen list with deliberate naming (names become shared vocabulary across PM / Visual / Frontend); user actions per screen; system responses; decision points; **error and edge states** (Plaid sync failure, stale data per Lock 11 cron, calculation-unavailable per Lock 15 as-of-date semantics, re-auth required, manual-entry conflict with synced data). Single-user constraint per [PRD §7.3](docs/PRD/index.html#sec-7-3) is load-bearing: flows assume one owner, no team/sharing/invite UI (V1-dormant `account_users` scaffolding does NOT surface in V1 UI per [ADR-011](DECISIONS.md#adr-011) Decision 6). **At each cluster close, invoke `subagent_type: product-manager` for a focused traceability pass** — every PRD story in the cluster has a corresponding flow; no flow extends scope beyond a PRD story; flow-implied requirements not in the PRD are flagged back to PM, not designed in unilaterally.

3. **Founder/CTO flow walk-through gate (review before wireframing — non-skippable).** Per the UX agent role definition: **do not wireframe until the flow it belongs to is reviewed and confirmed.** UX presents all six cluster flows end-to-end, pacing per `feedback_late_phase_density_overload` (small ratify gates beat a single mega-review on dense surfaces — likely two sittings: foundational §2.4 + read-surfaces §2.1/§2.2/§2.3 in one, then computation-heavy §2.5/§2.6 in the second; 1-sitting acceptable if cluster volume turns out lighter than expected). Two classes of decisions land here and **require 2–3 options with tradeoffs** per the UX agent role decision rules: (a) **navigation model** at app level (tabs vs. sidebar vs. drill-down — affects every screen); (b) **information-hierarchy** choices on the net-worth surface (single number vs. trend vs. breakdown) and the spending surface (calendar vs. category-tree vs. transaction-stream as the primary). **Both classes get DECISIONS.md ADR entries** (non-obvious cross-cutting decisions; future Phase 5 frontend + Phase 6 PR review benefit from rationale capture). Scope-impact items (flow implies a capability not in PRD §2) route to PM first, then F/CTO if V1-affecting. Wireframing does NOT start until F/CTO signs off on the flow set.

4. **Wireframe pass per major screen with interaction and error states (UX-lead).** Once flows are locked, UX produces wireframe-level detail for every screen in the locked screen list. For each wireframe: layout regions; component placeholders named per the established vocabulary (not styled — that's Visual's surface); **interaction states** per component (default / hover / pressed / loading / disabled / empty / stale / error); **error states** per screen aligned to known V1 failure surfaces from Phase 1 (Plaid item disconnected / re-auth required; sync stale beyond freshness threshold; as-of-date drill-back unavailable for a month with no checkpoint; monthly report not yet generated for target month; manual-entry validation failure). Density-first per [PRD §1.3 target-user archetype](docs/PRD/index.html#sec-1-3) — owner is technically literate; precision and density are features, hand-holding is not. Architecture constraints from Phase 3 (sync latency, data freshness, render-path composition per Lock 12) are consulted asynchronously as Architect's drafting crystallizes — Phase 2 does not block on Phase 3, but Architect is reachable for surgical questions via cross-team handoff.

5. **UX → Visual Designer handoff (gate to design-system work; Visual takes over at step 6).** UX produces the explicit handoff contract per the UX agent role definition, comprising four artifacts: (a) **screen list** — one row per screen across all six cluster flows, with screen name, parent flow, and PRD-story trace; (b) **component inventory per screen** — named primitives (button, input, table-row, metric-card, etc.) and composite components (account-row, allocation-ring, transaction-stream-item, monthly-report-section-block, etc.) — *what's needed, not how it looks*; (c) **interaction states** per component (the matrix from step 4); (d) **error states** per screen. **Critical coupling note baked into the handoff:** Visual's code-ready design-token deliverable (per Phase 2 Outputs) is **dependent on Architect's frontend-framework choice from Phase 3**, which is in flight in parallel per [ADR-012](DECISIONS.md#adr-012). If Architect's framework lock arrives before Visual reaches token output, no blocker; if Visual reaches token output before the framework lock, Visual either pauses on the framework-specific output step **or** emits tokens in a framework-agnostic intermediate format (e.g., Style Dictionary or W3C design-tokens JSON) with the framework-adapter layer deferred until Architect locks (F/CTO calls the path per step 10). Visual flags missing components back to UX rather than designing around them per the Visual agent role definition; UX does NOT hand off partial flows.

6. **UX→Visual handoff intake (Visual-led).** Consume UX Designer's step 5 handoff: the confirmed screen list, component inventory, and interaction/error-state notes per wireframe. Before any visual design begins, scan the handoff for ambiguity — undocumented interaction states, components referenced in wireframes but not in the inventory, conflicts between flow and wireframe artifacts. Any gap routes back to UX Designer via `SendMessage` for resolution; **do NOT design around ambiguity** (per the Visual Designer scope rule — flag UX gaps, don't fill them with visual choices). Confirm the handoff is complete and unambiguous before proceeding to step 7. The component inventory is the bounded surface — speculative components do not enter scope.

7. **Mandatory palette + typography F/CTO checkpoint (Visual-led; F/CTO gate).** Before drafting the full design system spec, Visual Designer presents **2–3 palette direction options** (e.g., neutral-first vs. accent-forward; light vs. dark baseline; warm vs. cool neutrals) and **2–3 typography system options** (e.g., single-typeface vs. display/body split; system-stack vs. self-hosted face), each with tradeoffs. **Pause for explicit F/CTO sign-off on both palette direction and typography system.** This checkpoint is mandatory per the Visual Designer role description — silence is not approval. F/CTO decisions recorded in `DECISIONS.md` as ADR-style entries. **Dark-mode support disposition also captured here** (plan-for vs. ship-with vs. defer-to-V2). Spec drafting does not begin until this gate closes.

8. **Design system spec drafting (Visual-led).** Once palette + typography are locked, Visual Designer drafts the design system spec: full typography scale (sizes, weights, line-heights, letter-spacing per role); full color token set (semantic — `color-text-primary`, `color-surface-elevated`, `color-border-default`, etc. — not value-named); spacing scale (semantic — `space-md`, `space-lg`, etc.); border-radius / shadow / elevation tokens; and component visual specs covering every component in UX's inventory with all states (default, hover, active, focused, disabled, error, loading where applicable). Each component spec references the tokens it consumes — no undocumented or ad-hoc values. Spec location: `/docs/design-system/` (or equivalent per F/CTO direction at phase entry). If a component spec surfaces a previously-unflagged UX gap, route back to UX Designer per step 6's discipline.

9. **Framework-agnostic token taxonomy (Visual-led; pre-Architect-gate).** While the design system spec is in flight, Visual Designer locks the **abstract token layer** — semantic names, scale steps, naming conventions, dark-mode variant strategy — independent of the eventual frontend framework. This is the layer that survives a framework swap. **Do NOT finalize the tokens-as-code (concrete file format, syntax) yet** — that step waits on Architect's Phase 3 framework-choice deliverable. Document the taxonomy in `/docs/design-system/` with rationale for naming conventions (semantic-over-value, scale-step rationale, dark-mode pairing approach). DECISIONS.md ADR captures the taxonomy lock.

10. **Architect framework-choice coordination + tokens-as-code finalization (Visual + Architect; Phase 3 coupling gate).** Phase 2 runs **parallel with Phase 3** per [ADR-012](DECISIONS.md#adr-012); the frontend framework choice is Architect's Phase 3 deliverable and is the coupling point for finalizing tokens-as-code. When Architect's framework-choice gate closes, Visual Designer coordinates with Architect (and Frontend Engineer if available) to confirm the token file format the framework can consume (e.g., Tailwind config, CSS custom properties, design-token JSON, framework-native theme objects) and presents 2–3 viable format options to F/CTO if more than one is plausible. F/CTO confirms format; Visual Designer then produces the concrete token file(s) at the agreed location, mapping the step-9 abstract taxonomy onto framework-consumable code. Token file is the canonical source — no manual translation downstream. **If Phase 3 framework choice slips substantially past Phase 2 spec readiness**, Phase 2 may exit via either path at F/CTO's call: (a) **pause** at "spec + taxonomy complete; tokens-as-code pending framework lock" until Architect ratifies (default); or (b) **emit a framework-agnostic intermediate format** (Style Dictionary, W3C design-tokens JSON, or equivalent) with the framework-adapter layer explicitly deferred to Phase 5 frontend setup. Both paths preserve the canonical-source discipline.

11. **Phase exit (team-lead-orchestrated).** After design system spec + abstract taxonomy + tokens-as-code (or intermediate-format fallback per step 10) are all complete:
   - Confirm exit criteria per the scaffold (every PRD story has a flow; every flow has wireframes; design system spec is unambiguous; tokens are in framework-consumable format OR intermediate-format with deferred-to-Phase-5 disposition documented).
   - Add Phase 2 "Lessons learned" subsection to WORKFLOW.md.
   - Update Phase 2 status to "✅ Complete" with completion date.
   - Bump WORKFLOW.md version and write the CHANGELOG.md entry.
   - Commit and merge via PR. **Do NOT advance the WORKFLOW.md header pointer to Phase 4 if Phase 3 is still in flight** — pointer stays at "Phase 2 + Phase 3 (parallel)" with Phase 2's section marked ✅ Complete in its own status. Phase 4 pointer activates only when BOTH phases close (per [ADR-012](DECISIONS.md#adr-012)). Team-lead (main session) handles the cross-phase orchestration per [ADR-009](DECISIONS.md#adr-009) Decision 1.

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

**Status:** 🟡 In progress (2026-05-27) — entered in parallel with Phase 2 per [ADR-012](DECISIONS.md#adr-012). Architect lead; consumes [ADR-011](DECISIONS.md#adr-011) + locks log (`temp/step-4-locks-log.md`) + 13 Phase 3 carry-over tasks.

**Detailed steps:**

1. **Pre-entry gates (Architect-led; F/CTO + Sec + PM consults).** Before any ARCH drafting, three entry-gate items resolve:
   - **Plaid production-tier monthly minimum confirmation** (out-of-band; F/CTO-driven sales/onboarding call). Per [ADR-011](DECISIONS.md#adr-011) Decision 20 this is the only load-bearing cost-target unknown — the cost projection ($15–$65/mo, mid-range ~$35/mo) holds only under a Plaid production-tier monthly minimum below the V1 budget. Resolution does NOT block ARCH drafting, but DOES block any Phase 3 lock that depends on the production-tier shape (notably the webhook handler + scheduled-poll architecture per [ADR-011](DECISIONS.md#adr-011) Decision 8 + Decision 17). Track as a Phase 3 task in the team tracker.
   - **Candidate P3 PM consult** — FMP API + stock-screening incumbent-exceeds-V1 surface. Per `feedback_incumbent_exceeds_v1_review`, the P3 V1-default disposition (ingest + no UI) per [ADR-011](DECISIONS.md#adr-011) Decision 20 requires PM ratification of "no V1 UI surface" before ARCH drafting touches the `pfin_back_etl` ingestion architecture. Invoke PM via `Agent(team_name="phase-3-arch-drafting", subagent_type="product-manager", name="pm")` with a P3-scoped brief; PM produces verdict (confirm / refine / reject) → ADR-011 amendment or BACKLOG.md update lands as needed.
   - **Team setup.** `TeamCreate phase-3-arch-drafting` at phase entry per [ADR-003](DECISIONS.md#adr-003). Architect is the workhorse (persistent context across the phase); Sec is mandatory joint-review at every architectural surface touch (see Step 3); PM is spawn-on-need for product-feasibility questions; Backend Engineer is consulted on implementation feasibility per the agents-involved scaffold. Mandatory pre-reading: `WORKFLOW.md`, `DECISIONS.md` (especially [ADR-011](DECISIONS.md#adr-011)), `temp/step-4-locks-log.md`, `docs/PRD/index.html`, `docs/SECURITY/index.html`, `.claude/agents/architect.md` + `.claude/agents/security-reviewer.md`.

2. **ARCH HTML §-by-§ drafting cadence (Architect-led, consuming ADR-011 + locks log).** `docs/ARCH/index.html` was scaffolded in PR A; Phase 3 drafts its content. Draft sections in the order V1-mandatory implementation surface flows, NOT the scaffold's section order — sequencing matters per [ADR-011](DECISIONS.md#adr-011) Consequences (Task #26 precedes #36; #32 follows #35):
   - **§ System overview + component diagram** (Architect only; consumes [ADR-011](DECISIONS.md#adr-011) Decision 17 hybrid-worker topology + `reference_pfin_back_etl` + `reference_hetzner_cax21`).
   - **§ Data model — tables, relationships, RLS policies** (Architect drafts; **Sec joint-review mandatory** — see Step 3). Consume [ADR-011](DECISIONS.md#adr-011) Decisions 5 / 6 / 7 / 10 / 11 / 12 / 13 / 14 / 15 / 16 / 18 / 19 + meta-patterns §7 (Decision 2) + §8 (Decision 3) in lockstep. Lock 9 → Lock 15 amendment (Task #26 → Task #36) sequencing is load-bearing — draft Lock 9 reconciliation tables FIRST then layer the Lock 15 `account_trans.created_at` re-introduction onto them.
   - **§ Plaid integration architecture** (Architect drafts; **Sec joint-review mandatory**). Consume [ADR-011](DECISIONS.md#adr-011) Decision 8 (Lock 4 — pgsodium + webhook signature + dedup) + Decision 1 (§6 privileged-context-write discipline).
   - **§ Auth strategy (Supabase Auth)** (Architect drafts; **Sec joint-review mandatory**). Consume [ADR-011](DECISIONS.md#adr-011) Decision 5 (Lock 1 — Option A baseline + selective C-on-A overlay) + Decision 7 (Lock 3 — `account_users.rd_access`-JOIN RLS shape including all 4 Sec V1-SHIP-BLOCK mods).
   - **§ Background worker architecture** (Architect drafts; **Sec joint-review mandatory**). Consume [ADR-011](DECISIONS.md#adr-011) Decision 17 (Lock 13 — `pfin_back_etl` extension + Node PDF worker + `TenantBoundConnection` class) + Decision 1 (§6) + Decision 4 (§10 — infrastructure-credential-absence as defense-in-depth layer).
   - **§ API surface** (Architect drafts; coordinate with Phase 2 — see Step 5).
   - **§ Security model + Backup/DR + Operational runbook starter** (Architect drafts; **Sec joint-review mandatory** on Security model). Backup/DR + runbook can ship at starter granularity; security model consumes the full §10 defense-in-depth discipline ([ADR-011](DECISIONS.md#adr-011) Decision 4).
   - **§ Deployment topology** (Architect only; consume Hetzner cax21 + Coolify-container-boundary framing per [ADR-011](DECISIONS.md#adr-011) Decision 17 + SECURITY §4.3 axis (vi)).

3. **Sec joint-review cadence (MANDATORY at every architectural surface touch).** Per `feedback_incumbent_exceeds_v1_review` + Phase 1 Step 4 lessons (Sec found 8 chain-attack catches Architect's drills missed at joint reviews), Sec joint-review is load-bearing — NOT advisory — at every Data model / Plaid / Auth / Worker / Security-model section lock. Pattern per surface:
   - Architect drafts the section with full options/tradeoff treatment for any Phase 3 decision NOT already locked at ADR-011 (e.g., pgsodium key-management mechanism per Decision 8; per-tenant-key-derivation for tenant-scoped-with-app-encryption classes per [ADR-011](DECISIONS.md#adr-011) Future ADR housekeeping note).
   - Invoke Sec via `SendMessage(to="sec")` (Sec persistent teammate) with section content + Architect's options + lean. Sec produces verdict: confirm / V1-SHIP-BLOCK mods / advisory mods.
   - Sec's V1-SHIP-BLOCK mods land in the section before F/CTO ratify-gate; advisory mods land at Architect discretion with rationale.
   - **Any Sec veto routes to F/CTO** — Architect does NOT self-adjudicate Sec verdicts per the agent definition. F/CTO ratifies the section with optional mod amendments (the Step 4 pattern produced 3 F/CTO clarification interventions on Locks 11 / 14 / 15 that materially changed Sec verdicts).

4. **Carry-over task consumption pattern (13 Phase 3 tasks from team tracker `phase-1-step-4`).** The 13 carry-over tasks — #11 / #13 / #15 / #16 / #17 / #20 / #26 / #29 / #32 / #33 / #34 / #35 / #36 — each carry their full Sec-mod inventory from Step 4 lock entries in `temp/step-4-locks-log.md`. Migrate the 13 tasks into the `phase-3-arch-drafting` team tracker at phase entry (preserve task numbers for cross-reference continuity). Consumption pattern per task:
   - Map task to the ARCH § it lands in (per Step 2 ordering).
   - At § drafting time, Architect verifies every Sec mod on the task lands in the ARCH text. V1-SHIP-BLOCK mods MUST appear; advisory mods land with rationale or get explicit defer-to-Phase-5-migration disposition.
   - Sec re-ping at § lock to verify all V1-SHIP-BLOCK mods landed (Sec compares ARCH § text against locks-log per-task Sec-mod list). Sec sign-off on the § closes the task.
   - Sequencing constraints per [ADR-011](DECISIONS.md#adr-011) Consequences: Task #26 (Lock 9 reconciliation) precedes Task #36 (Lock 15 Lock-9-amendment); Task #32 (Lock 11 monthly_report cron) follows Task #35 (Lock 14 settings table creation).

5. **Phase 2 coordination touchpoint — frontend framework choice (Architect-decided; Visual Designer-consuming).** Phase 3 runs PARALLEL with Phase 2 per [ADR-012](DECISIONS.md#adr-012). The single hard coupling point is the **frontend framework choice** — Architect's decision per the API surface § (Step 2) is the constraint Visual Designer needs to pick the design-tokens-format per Phase 2 exit criterion 4 ("Design tokens are in a format consumable by the chosen frontend framework"). Coordination:
   - Architect drafts the frontend framework decision with 2–3 options + tradeoffs (incumbent constraints: Supabase JS client + V1 app render path per [ADR-011](DECISIONS.md#adr-011) Decision 17 + PDF worker render-via-V1-app per Decision 17 mod #1).
   - F/CTO ratifies the framework choice. Architect notifies Visual Designer via cross-team `SendMessage` (routed through team-lead per ADR-012 coordination expectations) **immediately on ratify** — Visual Designer's design-tokens-format work blocks on this decision.
   - Other Phase 3 ↔ Phase 2 coordination is OPTIONAL — UX flows are "helpful but not required to start" per the Phase 3 Inputs scaffold; Phase 3 does NOT block on Phase 2 outputs except for any flow that materially constrains the API surface (Architect flags these case-by-case).

6. **Initial migration files in `/supabase/migrations/` (Architect-led; Sec advisory).** Phase 3 outputs include the initial migration set per the Phase 3 scaffold. Draft migrations in lockstep with the Data model § (Step 2) — one migration per logical lock-set (e.g., `001_users_id_rename.sql` per Decision 10; `002_account_users_v1_dormant.sql` per Decision 6; `003_reconciliation_event_family.sql` per Decisions 13 + 19 since Lock 9 + Lock 15 amendment land together; `004_account_trans_immutable.sql` per Decision 14; etc.). Conventions:
   - Migrations apply cleanly to a fresh Supabase instance (Phase 3 exit criterion).
   - Every migration includes the matched-tenant validation per Decision 3 (§8 meta-pattern) on FK-shaped columns; every audit-class table includes the immutability triggers per Decision 2 (§7 meta-pattern).
   - Sec re-reviews any migration touching a SD-NN storage class per [ADR-011](DECISIONS.md#adr-011) Consequences ("every migration touching a SD-NN class implements the storage-protection-class commitment"). Sec sign-off NOT required at Phase 3 exit (migrations finalize in Phase 5); Phase 3 ships the initial pass.
   - Phase 5 will iterate the migration set; Phase 3's job is to land a structurally-coherent starter set, not a production-ready one.

7. **Exit-criteria mapping (Architect verifies; F/CTO ratifies).** Before phase exit, Architect walks the 5 Phase 3 exit criteria and produces an explicit mapping:
   - **"All V1 PRD requirements have an architectural answer"** — cross-reference every PRD V1 user story (32 per `docs/PRD/index.html` §2) against the ARCH §s. Gap-list any unanswered story → resolve before exit.
   - **"Every major decision has an ADR in DECISIONS.md"** — Step 4 produced [ADR-011](DECISIONS.md#adr-011) as the canonical-reference layer; Phase 3 ADRs land for decisions NOT already covered by ADR-011 (pgsodium key-management, frontend framework, per-tenant-key-derivation if introduced, etc.). Each Phase 3 ADR follows ADR-011's "consolidation pattern" or the terse pattern per the DECISIONS.md preamble.
   - **"Schema migrations exist and apply cleanly to a fresh Supabase instance"** — verified via local `supabase db reset` or equivalent.
   - **"Security Reviewer signs off on auth, RLS, and secrets handling"** — Sec produces an explicit phase-exit sign-off message covering the relevant ARCH §s; any V1-SHIP-BLOCK mod NOT yet landed gates exit.
   - **"Founder/CTO signs off on the document as v1.0"** — F/CTO reads `docs/ARCH/index.html` end-to-end in one sitting and signs off explicitly in the team channel. Silence is not approval.

8. **Phase exit (Architect-led; team-lead coordination).** After ARCH lock at v1.0:
   - Add Phase 3 "Lessons learned" subsection to WORKFLOW.md (mirroring Phase 1 Step 4 lessons-learned shape — chain-attack catches Sec surfaced; meta-pattern refinements; sync-mismatch observations; F/CTO clarification interventions; project-canonical conventions established).
   - Update Phase 3 status to "✅ Complete" with completion date.
   - Update MILESTONES.md head — Phase 3 → complete; M1 milestone status (ARCH + SECURITY docs locked). **Do NOT advance the WORKFLOW.md header pointer to Phase 4 if Phase 2 is still in flight** — pointer stays at "Phase 2 + Phase 3 (parallel)" until both phases close per [ADR-012](DECISIONS.md#adr-012).
   - Update CHANGELOG.md with the per-PR ARCH-drafting narrative.
   - Phase 3 ADRs (newly-landed in this phase) are listed in the lessons-learned subsection for forward reference.
   - `TeamDelete phase-3-arch-drafting` after phase exit; any Phase 4+ work spawns a new team per [ADR-003](DECISIONS.md#adr-003).

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
- ~~`[OPEN]` Frontend framework choice — deferred to Phase 3 Architect proposal.~~ **Resolved 2026-05-29 at [ADR-015](DECISIONS.md#adr-015):** **SvelteKit (Svelte 5) + no Tailwind.** Architect's 3-option brief (Next.js / Remix / SvelteKit) with structural-comparison tables led to Architect lean Remix > Next > SvelteKit; F/CTO ratified SvelteKit on engineering-merit grounds against the lean (Lock 13 mod #1 SSR-by-default fit; ADR-014 token consumption 1:1 via Svelte scoped CSS; smallest container footprint; lowest framework ceremony). No Tailwind ratified subsequently — ADR-014's `--color-*` → `--c-*` CSS custom properties consumed natively. Phase-6 agent-fluency cost accepted explicitly.
- ~~`[OPEN]` Background worker technology — deferred to Phase 3 Architect proposal.~~ **Resolved 2026-05-26 at Lock 13 / [ADR-011](DECISIONS.md#adr-011) Decision 17:** hybrid architecture — `pfin_back_etl` Python ETL on Hetzner continues for data workers + V1 Node app handles Plaid webhook + monthly-report render + new Node PDF worker container handles PDF generation. See ADR-011 Decision 17 for the full inventory + Sec mods.
- ~~`[OPEN]` Backlog tooling: `TASKS.md` vs. GitHub Issues — deferred to Phase 4 entry.~~ **Resolved in v0.3:** Linear chosen, accessed via the official Linear MCP server. Operational details in `docs/linear-setup.md` (drafted in Phase 5). Cleanup of stale `TASKS.md` references completed in v0.5.
- `[OPEN]` Phase 4.5 practice feature — to be selected at Phase 4.5 entry.
- ~~`[OPEN]` Design tokens format — deferred to Phase 2 entry, depends on frontend choice.~~ **Resolved 2026-05-29 across [ADR-014](DECISIONS.md#adr-014) (taxonomy) + [ADR-015](DECISIONS.md#adr-015) (consumption):** two-tier CSS custom properties — `--color-*` primitives → `--c-*` semantic aliases in `docs/DESIGN/tokens.css`, imported globally in `src/app.css`, consumed natively via Svelte component-scoped `<style>` + `var(--c-*)`. No Style Dictionary, no design-token JSON intermediate, no Tailwind utility-class layer — the framework gets out of the way.

---

*End of WORKFLOW.md v1.41*
