# WORKFLOW.md

**Project:** mosko-fintech
**Current version:** v1.0
**Last updated:** 2026-05-08
**Current phase:** Phase 0 — Discovery & Operating Model (complete). Next: Phase 0.5 — Agent Roster Definition.

---

## Changelog

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

---

## Agent roster

Nine roles total. Each role has a corresponding `/agents/<role>.md` file containing its system prompt, scoped tools, and behavioral guidelines. Agent definitions are split across two phases by when they're first needed: roles active in Phases 1–4 are defined in **Phase 0.5**; build-time roles activated in Phase 5+ are defined in **Phase 5** alongside the rest of workshop setup. The "Definition timing" note on each role below indicates which phase produces its definition file.

### Meta role

**Chief of Staff** (`/agents/chief-of-staff.md`)
The orchestrator. Maintains WORKFLOW.md, ensures phase transitions are clean, escalates when execution agents drift outside their roles, and is the agent the Founder/CTO talks to when unsure which agent to engage. Does not execute on the build itself. Primary artifact: WORKFLOW.md.
*Definition timing:* Phase 0.5 (formalization of the role that has been operating informally since Phase 0).

### Execution roster

**Product Manager** (`/agents/product-manager.md`)
Owns PRD.md. Translates owner intent into structured user stories and feature definitions. Pushes back on scope creep. Maintains the V1 vs. V2 boundary. Co-piloted by Founder/CTO; Founder/CTO has final say on scope.
*Definition timing:* Phase 0.5 (lead on Phase 1).

**Architect** (`/agents/architect.md`)
Owns ARCHITECTURE.md. Proposes system designs, data models, service boundaries, and tech choices. Always presents options with tradeoffs. Flags one-way doors and migration debt. Defaults to boring patterns; requires justification for novel ones. Co-piloted by Founder/CTO; Founder/CTO signs off on all architectural decisions.
*Definition timing:* Phase 0.5 (consulted in Phase 1; lead on Phase 3).

**UX Designer** (`/agents/ux-designer.md`)
Owns user flows and interaction patterns. Translates PRD user stories into navigable flows. Hands off to Visual Designer. Reviewed by Founder/CTO; substantive UX decisions confirmed before execution.
*Definition timing:* Phase 0.5 (lead on Phase 2).

**Visual Designer** (`/agents/visual-designer.md`)
Owns the design system — typography, color tokens, component inventory, visual polish. Outputs code-ready tokens. Operates from UX flows. Fully delegated.
*Definition timing:* Phase 0.5 (lead on Phase 2).

**Security Reviewer** (`/agents/security-reviewer.md`)
Non-optional for fintech. Reviews every PR touching auth, data handling, external APIs, secrets, or financial calculations. Has veto power. Co-piloted by Founder/CTO; Founder/CTO signs off on all security-flagged changes.
*Definition timing:* Phase 0.5 (consulted in Phase 1; lead reviewer on Phase 3 auth/data/secrets work).

**Backend Engineer** (`/agents/backend-engineer.md`)
Implements API, data layer, Plaid integration, background workers. Operates against Architect's contracts. Reviewed by Founder/CTO; SQL and Python output specifically reviewed by Founder/CTO given owner fluency.
*Definition timing:* Phase 5 (build-time role; deferred until tech stack and patterns are real).

**Frontend Engineer** (`/agents/frontend-engineer.md`)
Implements UI against the design system and API contracts. Fully delegated; Founder/CTO reviews PRs but does not co-pilot.
*Definition timing:* Phase 5 (build-time role; deferred until frontend framework and design system are real).

**QA** (`/agents/qa.md`)
Generates and maintains test suites. Writes acceptance tests against PRD user stories. Founder/CTO defines acceptance criteria; QA agent operationalizes them.
*Definition timing:* Phase 5 (build-time role; deferred until test framework and acceptance patterns are real).

**DevOps** (`/agents/devops.md`)
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

### Agent definitions (`/agents/`)

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
| 0.5 | Agent Roster Definition | ⏳ Not started | Agent definition files for Phase 1–4 roles |
| 1 | Product Definition (PRD) | ⏳ Not started | `PRD.md` |
| 2 | UX & Design | ⏳ Not started | User flows + design system |
| 3 | Technical Architecture | ⏳ Not started | `ARCHITECTURE.md` (revised from existing schema) |
| 4 | Project Scoping | ⏳ Not started | Linear backlog (initiatives, projects, issues) |
| 4.5 | Agentic Flow Ramp | ⏳ Not started | Practice feature + workflow fluency |
| 5 | Workshop Setup | ⏳ Not started | `CLAUDE.md` files, build-time `/agents/*.md`, `/skills/*.md`, CI/CD |
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

**Purpose:** Stand up the team. Phase 0 defined *what* the agent roster is at a high level; Phase 0.5 produces the actual agent definition files (`/agents/*.md`) for the roles that will be active in Phases 1–4. Each definition contains the agent's system prompt, scoped tools, behavioral guidelines, escalation patterns, and Linear permission policy. After this phase, when Phase 1 says "Product Manager leads," there is a real PM agent file to invoke.

Build-time roles (Backend Engineer, Frontend Engineer, QA, DevOps) are deliberately deferred to Phase 5, where their context (stack, framework, design system, CI patterns) is real. Defining them here would mean writing prompts in a vacuum and rewriting them later.

**Inputs:**

- Operating model and agent roster from Phase 0 (this document)
- Linear MCP setup decisions from v0.3 (Linear is the task tracker; agents access via the official Linear MCP server with scoped permissions)
- Owner's understanding of how each role behaves in practice (refined informally during Phase 0)

**Outputs:**

- `/agents/chief-of-staff.md` — formalizes the role that has been operating informally since Phase 0 began
- `/agents/product-manager.md` — Phase 1 lead
- `/agents/architect.md` — Phase 1 consultant, Phase 3 lead
- `/agents/security-reviewer.md` — Phase 1 consultant, Phase 3 reviewer
- `/agents/ux-designer.md` — Phase 2 lead
- `/agents/visual-designer.md` — Phase 2 lead
- `DECISIONS.md` entries for any non-obvious choices in agent prompt design (e.g., scope of veto power, escalation triggers, when an agent must present options vs. just decide)

**Agents involved:**

- Chief of Staff (lead — drafts its own definition first, then uses it to draft the rest)
- Founder/CTO (reviews and signs off on each definition; veto on any prompt that gives an agent more authority than intended)

**Exit criteria:**

- Six agent definition files exist in `/agents/`, each containing: role description, system prompt, scoped tools, behavioral guidelines, escalation triggers, Linear permission policy
- Chief of Staff agent can be invoked and produces orchestration-style responses, not execution-style responses
- Each Phase 1–4 agent can be invoked and stays within its role boundaries (validated by a brief test prompt for each)
- Founder/CTO has reviewed every prompt and signed off
- `DECISIONS.md` exists (created here if not earlier) and contains entries for any contentious prompt-design choices

**Status:** ⏳ Not started

**Detailed steps:** *To be fleshed out before phase entry. First step will be drafting the Chief of Staff definition (so the role doing the agent-definition work gets formalized first), then the other five in dependency order: PM and Architect together (since they overlap in Phase 1), Security Reviewer next (informs the others' escalation patterns), then UX Designer and Visual Designer.*

**Lessons learned:** *To be added after phase exit.*

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
- **Agent definitions for Phase 1 roles** (from Phase 0.5): `/agents/product-manager.md`, `/agents/architect.md`, `/agents/security-reviewer.md`, `/agents/chief-of-staff.md` all exist and are signed off
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

**Detailed steps:** *To be fleshed out before phase entry. First step will be a ratification pass over Phase 0's preliminary findings — confirming, revising, or rejecting each before structuring the rest of the PRD around them.*

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
- Existing agent definitions from Phase 0.5 (`/agents/chief-of-staff.md`, `/agents/product-manager.md`, `/agents/architect.md`, `/agents/security-reviewer.md`, `/agents/ux-designer.md`, `/agents/visual-designer.md`)
- Lessons from Phase 4.5
- Owner's existing GitHub setup

**Outputs:**

- Root `CLAUDE.md` with project conventions
- Per-directory `CLAUDE.md` files for `/supabase`, `/api`, `/web`, `/workers` (or analogous structure)
- **Build-time agent definitions** added: `/agents/backend-engineer.md`, `/agents/frontend-engineer.md`, `/agents/qa.md`, `/agents/devops.md` — each with system prompt, tool scopes, behavioral guidelines, and **Linear permission scope** (which issues it may read, comment on, update status on, or create)
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

- ~~`[OPEN]` Agent prompt files (`/agents/*.md`) — slated for Phase 5 drafting. Confirm timing or pull earlier if needed.~~ **Resolved in v0.4:** split across Phase 0.5 (Phase 1–4 roles) and Phase 5 (build-time roles). See agent roster section.
- `[OPEN]` Frontend framework choice — deferred to Phase 3 Architect proposal.
- `[OPEN]` Background worker technology — deferred to Phase 3 Architect proposal.
- ~~`[OPEN]` Backlog tooling: `TASKS.md` vs. GitHub Issues — deferred to Phase 4 entry.~~ **Resolved in v0.3:** Linear chosen, accessed via the official Linear MCP server. Operational details in `docs/linear-setup.md` (drafted in Phase 5). Cleanup of stale `TASKS.md` references completed in v0.5.
- `[OPEN]` Phase 4.5 practice feature — to be selected at Phase 4.5 entry.
- `[OPEN]` Design tokens format — deferred to Phase 2 entry, depends on frontend choice.

---

*End of WORKFLOW.md v1.0*
