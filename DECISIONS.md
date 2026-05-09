# DECISIONS.md

Architectural Decision Records for mosko-fintech. Each entry captures a non-obvious choice: what was decided, what was considered, why.

**Format.** One ADR per H2 heading, numbered sequentially. Newest at top. Entries are immutable once accepted — supersede via a new entry rather than rewriting an old one. Status values: `Proposed`, `Accepted`, `Superseded by ADR-NNN`, `Deprecated`.

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
