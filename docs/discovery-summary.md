# mosko-fintech: Discovery Conversation — Pivot Points Summary

**Document version:** v0.2
**Date:** 2026-04-24
**Context:** Initial discovery and workflow definition conversation for the mosko-fintech project.
**Purpose:** Document the inflection points in the conversation where thinking shifted, decisions crystallized, or framing changed. Captured as a learning artifact for the project owner's first time building a product this way.

**Revision notes:**

- **v0.2** — Added Pivot 14 (separating *how the team operates* from *what the team builds*) to capture the late-conversation restructure of WORKFLOW.md from v0.1 to v0.2. Added corresponding Principle 14. Adjusted Pivot 12 framing slightly to acknowledge that document structure pivots continued past the v0.1 lock. Added the mini-business framing point to the "What I would do differently next time" section. **Final version of this document — no further updates planned.**
- **v0.1** — Initial draft. Thirteen pivots from the discovery conversation through WORKFLOW.md v0.1 delivery.

---

## How to read this document

Each pivot point follows the same structure:

- **The shift** — what changed in thinking
- **Why it mattered** — the consequence
- **Transferable principle** — what to take forward into future projects

Pivots are listed in conversational order, not importance order. The most consequential ones tend to come early (foundational decisions cascade) and at moments of disagreement or revision (where assumptions surfaced).

---

## Pivot 1 — Workflow before tooling

**The shift:** The conversation opened with the question "do I start with Claude Design? Claude Code? Projects?" The first response reframed this: *tooling follows definition, not the other way around*. Don't open Claude Code yet.

**Why it mattered:** The most common failure mode in AI-assisted builds is treating tool setup as progress. Code written against an imaginary spec gets retrofitted with a PRD, then the data model can't support half the actual features. Starting with definition prevents weeks of throwaway work.

**Transferable principle:** When a project feels exciting and you want to start building, that's the signal to slow down and define. The exciting part isn't the work — it's the planning compressed into a moment of impatience.

---

## Pivot 2 — Sequential discovery questions, one at a time

**The shift:** Instead of a bulk questionnaire ("answer these 10 things"), discovery was structured as four sequential questions, each followed by reflection on what the answer changed downstream.

**Why it mattered:** Each answer's implications were absorbed before the next question was asked. The "personal but with friends-and-family path" answer to question 1, for example, immediately changed the framing of every subsequent question — auth, data model, hosting, compliance posture — and that change was made visible *before* asking question 2.

**Transferable principle:** For definitional work, sequence questions and reflect after each. Bulk questionnaires produce shallow answers because the respondent doesn't see the consequences of their answers playing out.

---

## Pivot 3 — "Just me" → multi-tenant from day one

**The shift:** The user's answer ("just me, but maybe friends and family later") was treated as having immediate architectural consequences, not as a "future problem." Multi-tenancy was locked into the data model from V1 even though the UI would remain single-user-only for months.

**Why it mattered:** Retrofitting `user_id` onto every table in an existing app is one of the most painful refactors in software. Doing it from scratch costs nothing. The "I'll add it later" version of this decision is one of the classic indie-developer regrets.

**Transferable principle:** When a future possibility has cheap upfront cost and expensive retrofit cost, treat it as present-day requirement. The asymmetry, not the probability, is what should drive the decision.

---

## Pivot 4 — Six use cases → four clusters → V1 = two clusters

**The shift:** The user listed six "broad strokes" use cases. Rather than treat them as siblings, they were grouped into four clusters by data model and dependency: foundational (net worth + allocation), separate-data (budgets), projection-layer (tax + Monte Carlo), and standalone (stock screening). V1 was scoped to the two clusters that already exist in the user's manual workflow.

**Why it mattered:** Without clustering, V1 would have been all six features, taken many months, and probably never shipped. The clustering revealed that some "features" are actually the substrate everything else depends on, and others are essentially separate apps in disguise.

**Transferable principle:** When a feature list contains 5+ items, look for clusters by *data model* and *dependency*, not by category labels. The clusters tell you what's foundational, what's an addition, and what should probably be a different project.

---

## Pivot 5 — "Replacing manual work" forces real integration

**The shift:** When the user said V1 should *replace* their current manual workflow (not augment it), the data source decision became forced: Plaid, not CSV imports. The phrase "replacing manual work" was treated as a constraint that ruled out half-measures.

**Why it mattered:** Many personal finance projects fail because they introduce *new* manual work (CSV exports, reconciliation) while not eliminating the old. The clarity of "replace, not augment" forced an architectural choice that has real cost (Plaid subscription) but matches the actual goal.

**Transferable principle:** Be explicit about whether you're replacing or augmenting. They demand different architectures and different cost profiles.

---

## Pivot 6 — Plaid is the locked choice, but abstracted

**The shift:** Plaid was selected after evaluating alternatives (Teller, MX, Finicity, SnapTrade, Yodlee). But rather than couple the codebase tightly to Plaid, the architecture was specified to include an *aggregator-abstraction layer* — Plaid as the first concrete implementation, swappable later.

**Why it mattered:** Vendor decisions in fintech tend to lock you in for years. The abstraction layer costs ~half a day of architectural design and buys real optionality. It also forces you to think about what data shape your app actually wants, separate from what any vendor returns.

**Transferable principle:** When picking a vendor for something foundational, design the integration as if you'll switch. You probably won't, but the design discipline of "what does our app actually need" produces cleaner code regardless.

---

## Pivot 7 — Honest answers about cost uncertainty

**The shift:** When the user asked about Plaid's costs beyond the free trial, the answer was "I'll search, but Plaid has gotten cagey about publishing rates — anyone quoting exact numbers is guessing or repeating outdated figures." A defensible cost *range* with honest uncertainty replaced fake precision.

**Why it mattered:** Treating uncertainty as something to communicate clearly, rather than paper over with confident-sounding numbers, builds trust and prevents budgeting surprises. The user got actionable cost guidance ($10–40/month at small-family scale) without being misled into thinking that number is precise.

**Transferable principle:** When precision isn't available, give a defensible range with the boundaries of your confidence. This is more useful than either "I don't know" or fake exact numbers.

---

## Pivot 8 — "Position-only" → "Lots in schema, positions in UI"

**The shift:** The original recommendation was position-level holdings (no lots) for V1 simplicity. When the user asked "should I just start with lots to ease future migrations?", the recommendation was *revised* — yes, capture lots in the schema from day one, but only expose positions in the V1 UI.

**Why it mattered:** Two things. First, the actual complexity of "lots" lives in the UI, not the schema; the original framing conflated them. Second, the migration cost of adding lots later is dramatically higher than capturing them upfront because Plaid won't backfill historical lot data. The user's instinct was right and corrected the original recommendation.

**Transferable principle:** When recommending against complexity, separate "schema complexity" from "UI complexity" from "operational complexity" — they have different costs and different migration paths. And: when the user pushes back on a recommendation, examine whether the pushback reveals a flawed assumption rather than defending the original answer.

---

## Pivot 9 — "Solo" doesn't mean "less process"

**The shift:** When the user confirmed they were a solo builder, the natural assumption would be "skip the formal process." Instead, the framing was: solo *removes* certain process needs (coordination, code review SLAs) but *adds* others (decision logs, externalized scope discipline, written-for-future-self documentation).

**Why it mattered:** Solo founders often skip documentation because "I'll remember." Three months later, returning from a context switch, they don't. Documentation isn't bureaucracy when you're solo — it's a message to your future self, who is effectively a different person.

**Transferable principle:** Solo doesn't mean lightweight process. It means *different* process — heavier on writing things down, lighter on coordination overhead. The friction a team would create has to be externalized into artifacts and explicit rituals.

---

## Pivot 10 — CTO + Architect agent pairing

**The shift:** The user requested an Architect agent because their EE/algorithms background didn't extend to fintech-specific architectural patterns. The framing that landed: the user is the **CTO** (judgment, decisions, constraints), and the Architect agent **proposes** designs the CTO accepts, modifies, or rejects.

**Why it mattered:** Pure delegation to an Architect agent would mean rubber-stamping designs you don't understand. Pure self-architecting would waste the agent's pattern knowledge. The split — Architect proposes with tradeoffs, CTO decides — preserves both leverage and judgment.

**Transferable principle:** For roles where you have the judgment but not the pattern library, structure the agent as a *proposing* entity and yourself as a *deciding* entity. Always require the agent to present 2–3 options with tradeoffs for non-trivial decisions.

---

## Pivot 11 — Naming the Chief of Staff role

**The shift:** Late in the conversation, the user asked "what role are you playing in this conversation?" The honest answer was that I had been operating as a fused PM + Architect + Workflow Designer — a meta-role distinct from the eight execution agents we had defined. We named this role explicitly: **Chief of Staff**.

**Why it mattered:** The whole point of the agent roster is role separation. An unnamed, omniscient meta-agent doing everything would silently undermine the structure. Naming the role made the separation real and gave it a defined scope (orchestration, not execution).

**Transferable principle:** When working with AI agents, periodically ask "what role is this agent currently playing?" If the answer is "all of them" or "I'm not sure," that's a sign that role boundaries are dissolving and need to be redrawn explicitly.

---

## Pivot 12 — WORKFLOW.md as both map and execution log

**The shift:** The user noticed a tension: the workflow document is supposed to be read first (a stable reference), but also updated as we progress (a living log). The resolution: it serves both roles, with stable scaffolding fully drafted in v0.1 and per-phase detail expanded just-in-time. The structure also turned out to need real revision after v0.1 (see Pivot 14), validating the versioning approach.

**Why it mattered:** Without resolving this, the document would either be incomplete-but-current or complete-but-stale. The dual-role framing — with explicit guidance on what gets fleshed out when, plus a versioning scheme — made it possible to have a complete map from day one without committing to speculative detail about distant phases, *and* to revise foundational structure (like the Phase 0 / Phase 1 boundary) without breaking the document.

**Transferable principle:** Documents that need to be both reference material and status logs should be designed deliberately for both roles, with explicit guidance on what's stable and what's living, plus a versioning scheme that tracks the changes. Build in the assumption that even "stable scaffolding" will need revision — the versioning is what makes that survivable.

---

## Pivot 13 — Inserting Phase 4.5 (Agentic Flow Ramp)

**The shift:** When the user mentioned unfamiliarity with the agentic flow despite a Claude Code trial, the workflow added an explicit half-phase between scoping and workshop setup: a deliberate practice feature to internalize the loop *before* doing real V1 work.

**Why it mattered:** Learning a workflow while shipping real code is the worst possible time to learn it. Mistakes get baked into the codebase, patterns get set badly, and "I'll fix it later" debt accumulates. A throwaway practice feature converts learning-time into something disposable.

**Transferable principle:** When a project depends on a workflow you don't yet have, build a throwaway practice round before committing to real work. The cost of one extra week of practice is dramatically less than the cost of bad patterns shipped into production.

---

## Pivot 14 — Separating "how the team operates" from "what the team builds"

**The shift:** After WORKFLOW.md v0.1 was delivered, the user pushed back on the framing of Phase 0. Phase 0 had been doing two distinct jobs at once — establishing the operating model (how the mini-business runs) and locking V1 product scope (what the mini-business builds). The user reframed the project as "mini-business with startup feel" and asked for Phase 0 to focus on the founding-meeting work, with product specification deferred to Phase 1. WORKFLOW.md was revised to v0.2 to reflect this: Phase 0 now produces operating model + workflow + foundational artifacts; product findings from discovery move to Phase 1 as **inputs to be ratified**, not as Phase 0 outputs.

**Why it mattered:** Conflating "how" and "what" obscures what's actually foundational. The operating model rarely changes after Phase 0 — it's the spine of the project. Product scope changes constantly during PRD work, architecture, and even implementation. Treating them as the same kind of artifact, locked at the same time, creates false confidence about product decisions and false anxiety about operating-model decisions. The split also matches how a real startup actually sequences work: founders agree on roles and decision rights *before* the product spec exists, not as part of it. Naming the project a "mini-business" rather than a "personal coding project" was the framing shift that made the rest of the restructure obvious.

**Transferable principle:** When you find yourself making structural decisions about *how to work* and structural decisions about *what to build* in the same artifact, separate them. The operating model lives in one document and changes rarely; product scope lives in another and changes often. Conflating them makes both harder to evolve. As a corollary: the framing you choose for the project ("personal coding project" vs. "mini-business" vs. "research prototype") quietly determines what counts as a foundational decision and what counts as a product decision.

---

## Principles extracted

A condensed set of meta-principles that emerged from the conversation:

1. **Define before you build.** Tooling is downstream of definition.
2. **Sequence definitional questions; reflect after each.**
3. **Treat cheap-now / expensive-later asymmetries as present-day requirements.**
4. **Cluster features by data model and dependency, not by category.**
5. **Be explicit about replace-vs-augment intent.**
6. **Design for vendor swap-ability even if you never swap.**
7. **Communicate uncertainty as a range with confidence bounds, not fake precision.**
8. **Separate schema, UI, and operational complexity when reasoning about cost.**
9. **Solo work demands more writing, not less process.**
10. **Pair "judgment" roles (you) with "pattern" roles (agents); require options with tradeoffs.**
11. **Name agent roles explicitly; resist omniscient meta-agents.**
12. **Documents that are both reference and log need explicit dual-role design.**
13. **Practice the workflow before shipping with the workflow.**
14. **Separate "how the team operates" from "what the team builds";** the framing you choose for a project (hobby, mini-business, prototype) determines which is which.

---

## What I would do differently next time

A short list, written from the position of finishing this conversation:

- **Frame the project explicitly as a mini-business from message one.** This was the framing the user landed on at the end, and it would have made the rest of the structure obvious from the start — Phase 0 as the founding meeting, Phase 1 as the first piece of real work, agent roles as actual team members. Without that framing, the conversation defaulted to a generic "personal coding project" mode that conflated *how the team operates* with *what the team builds*.
- **Ask question 1 (user scope) even faster.** It cascades into everything else, and waiting until question 1 to think about multi-tenancy means the first answers about features get reframed retroactively.
- **Surface the cost question earlier.** Plaid pricing came up after V1 scope was locked. Knowing the cost shape during scope discussion would have prepared the user for the financial-commitment side of the V1 decision.
- **Name the Chief of Staff role at the start, not the end.** It would have made the role-separation discipline explicit from the first message rather than being a late retrofit.
- **Draft the agent roster as a sketch earlier in discovery**, even knowing it would be revised, so that the role-separation discipline could be applied to the discovery work itself.

These are small refinements, not corrections. The conversation produced a sound foundation. But they're worth noting for the next time you (or anyone) does this.

---

*End of pivot points summary*
