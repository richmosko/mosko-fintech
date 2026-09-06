---
name: pdf-worker-pulls-html-it-is-not-pushed-json
description: SUPERSEDED as live state by R2 (C) 2026-09 — the app now PUSHES finished HTML and the worker is a PDF printer. Kept for its still-live lesson: read the ARCH sequence diagram before drafting either side of a cross-container hop, and direction decides who owns escaping.
metadata:
  type: reference
---

⚠ **SUPERSEDED AS LIVE STATE, 2026-09-06.** The V1.5 sitting ruled **R2 (C)**: the app composes under the user's own session, renders the shared Svelte template, and **PUSHES finished HTML** to the worker, which is *"a PDF printer, nothing else"* — exactly the *third option* this note flagged as worth keeping (last paragraph). `/internal/pdf-render` is **retired as an app route**; ARCH §3.2 and RT-21 are the artifacts that were wrong, and SD-20 — the outlier called out below — was **right all along**. Read the live record before citing anything here as current.

What follows is the 2026-08 state, kept for the reasoning, not the direction.

**The PDF worker pulls; it is not pushed to.** `docs/ARCH/index.html` §3.2's sequence diagram, verbatim in order: worker mints JWT → `PW->>V1: "GET /internal/pdf-render + signed JWT"` → V1 verifies (RT-21) → V1 calls the INVOKER helper → DB returns data → **`V1-->>PW: Rendered HTML`** → Puppeteer → PDF. SECURITY RT-21 agrees (*"V1 app `/internal/pdf-render` endpoint verifies inbound JWT **from PDF worker**"*); ADR-011 Decision 17 / Lock 13 agrees (*"Puppeteer browser-context-per-render hitting V1 app render URL"*).

Three V1.5 drafted ACs (A4/SELF-348, A5/SELF-349, P6/SELF-358) had the app pushing a composed JSON payload to the worker and receiving PDF bytes. ⚠ **Likely provenance, and it is a trap worth naming: the provider-sync worker genuinely does use an app→worker admission hop** (ADR-027 amendment (hh) / RT-27 / SELF-212, `:8081`). RT-21's own body warns about exactly this: *"Two clauses that read as siblings have different attacker models and therefore different right answers — reasoning from the resemblance produces a confident wrong answer for one of them."*

**Why the direction is load-bearing, not a wording nit.** Pull direction ⇒ the app's Svelte template is the single render path, so "PDF layout matches in-app" is structural, and **BACKLOG §7.32 item 6's `schedule_label` escaping hazard is discharged by Svelte's default escaping** — no user prose is ever composed into HTML inside the worker. Push-JSON direction ⇒ a second HTML template inside a zero-DB container with no escaping framework, and §7.32 item 6 becomes a mandatory, testable control. **The inverted draft creates the hazard a V1.4 Sec finding already booked against V1.5.**

⚠ **SD-20's own cell reads the other way** (*"PDF worker verifies signature + freshness + nonce"*) — a pre-existing ambiguity inside the SECURITY doc. Lock 13 + RT-21 + ARCH §3.2 are three-to-one; SD-20's clause is the outlier.

**How to apply:** before drafting either side of a cross-container hop, read the ARCH sequence diagram for that hop — it is the only artifact that states direction unambiguously. A third option worth keeping: **app pushes rendered HTML** (not JSON), which keeps one template and structural escaping *and* dissolves the "how does a non-JWT caller bind a tenant identity" problem entirely, at the cost of a Lock 13 amendment. Related: [[feedback_false_composite_citation]], [[reference_lock_join_lists_are_dated_artifacts]].
