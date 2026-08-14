---
name: address-teammates-by-name-not-type
description: SendMessage takes the teammate's short NAME (frontend, backend, qa, sec, pm, ux, visual) — the agent TYPE from the tool listing does not resolve, and ListAgents cannot see in-process teammates
metadata:
  type: feedback
---

**Address teammates by their short spawn NAME**, not by the agent-type string in the
Agent tool's listing:

| works | does NOT resolve |
|---|---|
| `frontend` `backend` `qa` `sec` `pm` `ux` `visual` | `frontend-engineer` `backend-engineer` `security-engineer` `product-manager` `ux-designer` `visual-designer` |

**Why:** 2026-08-12 — sent to `frontend-engineer`, got *"No agent named … is reachable"*,
and **wrongly concluded the teammate did not exist.** Reported it to team-lead as a
roster gap. It was a bad address. QA hit the identical trap with `backend` earlier the
same day, so it is a recurring class rather than a one-off.

⚠ **The reasoning failure is the part worth keeping, not the name list.** I had already
messaged `backend`, `qa` and `pm` successfully in the same session — **the evidence that
short names are the addressing form was in my own history**, and I still read the bounce
as absence rather than as a wrong address.

**`ListAgents` made it worse rather than better: it returns peer SESSIONS and Remote
Control peers, NOT in-process teammates.** So it came back without `frontend` listed,
which looked like confirmation. It was silence from an instrument that structurally
cannot see the thing being looked for — `062`'s near-miss (10) exactly: *"I asked a
question that could not return the roles I hadn't thought of, and read its silence as
absence."*

**How to apply:**
- On a `No agent named X is reachable` bounce, **check the address form before
  concluding anything about the roster** — compare against a name you have already
  messaged successfully this session.
- **Do not treat an empty `ListAgents` row as evidence a teammate is absent.** It does
  not enumerate in-process teammates; its silence carries no information about them.
- Surfacing the apparent gap to team-lead rather than guessing at names was still the
  right move — the error was in the *diagnosis* I attached, not in escalating.
