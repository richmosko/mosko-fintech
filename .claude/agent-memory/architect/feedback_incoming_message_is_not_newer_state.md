---
name: incoming-message-is-not-newer-state
description: An arriving message is not automatically more current than what you already know — a teammate's document describes its own moment, and twice in one day I took the newer message over the disproof already in my own history
metadata:
  type: feedback
---

**An incoming message is not automatically a more recent state than what you already
know.** A teammate's document, brief, or framing **describes the moment it was written**
— treat it exactly like a teammate's measurement: *true when taken*, and a different
claim from *true now*.

**Why — two instances, same day, same shape:**

1. **`frontend-engineer` bounce (2026-08-13).** Sent to the agent *type* instead of the
   *name*, got `No agent named … is reachable`, and concluded **the teammate did not
   exist** — while my own message history held successful sends to `backend`, `qa` and
   `pm`, all short names. See [[address-teammates-by-name-not-type]].
2. **SELF-221 §0.** Team-lead's build dispatch **opened with F/CTO's ratify of option
   (B)** — the ratify was the only reason I was authoring the migration at all. PM's
   holder document then reached me framing §0 as *"the single blocking F/CTO decision"*,
   and **I echoed that back as live state** in my own status report, without reconciling
   it against the instruction I was mid-execution on. PM's framing was **accurate when
   PM wrote it** and stale by the time it arrived.

> **The common thread: the disproof was already in my own history, an incoming message
> contradicted it, and I took the incoming message.**

**Why it is seductive:** a newer message *usually* is newer state, so the heuristic is
right most of the time. It fails precisely where documents are authored in parallel —
which is exactly when several agents are working one item, i.e. when it matters.

**How to apply:**
- ⚠ **A holder document is not a status feed.** Its "open questions" section is a
  snapshot of that author's moment. Before repeating one as current, check it against
  the dispatch you are executing.
- **When an incoming claim contradicts something you already acted on, the thing you
  acted on is evidence** — reconcile them explicitly rather than letting recency decide.
- **Say which one you checked.** "§0 is closed per the build dispatch" is verifiable;
  "§0 is blocking" repeated from a document is not.
- Corollary already learned elsewhere and the same family: never forward a sha, count or
  status a teammate reported — re-read it in the same turn you relay it.

Related: [[address-teammates-by-name-not-type]] · [[spot-check-the-contract-at-its-consumer]]
