---
name: project-lock13-mod2-and-adr072-a4-are-narrower-than-their-names
description: Two ratified predicates whose common shorthand is broader than the locked text — Lock 13 mod #2 is credential-and-client absence (NOT network isolation), and ADR-072 Amendment 4's written-statement obligation applies only to mechanism (a)
metadata:
  type: project
---

Two Lock/ADR predicates that are routinely cited by a name broader than what was ratified.
Both were load-bearing on a veto decision in the PR #844 (W-1) review, 2026-09-20.

**1. Lock 13 mod #2 is a CREDENTIAL-AND-CLIENT-ABSENCE fence, not a network fence.**
ADR-011 Decision 17's locked option, verbatim: *"V1-SHIP-BLOCK PDF worker no-direct-DB-access
infrastructure fence (no `SUPABASE_*` env vars; no Postgres client installed; §10 meta-pattern
instance per Decision 4 — infrastructure-credential-presence layer)"*. `docs/SECURITY/index.html:498`
agrees verbatim: *"infrastructure-credential-absence fence"*. The names in circulation —
"zero-DB-isolation", "no-direct-DB-access", "zero DB reach" — all describe the **goal**; the fence is
the two clauses, enforced by RT-22 (Dockerfile) + RT-22-manifest (dependency manifest).
Giving `pdf-render` a network route to `db:5432` does **not** engage mod #2. ADR-073 Consequence 4:
*"The network is not the control."*

**2. ADR-072 Amendment 4's written-statement obligation is MECHANISM-(a)-CONDITIONED.**
A4 offers two attachment mechanisms and closes: *"Prefer (b); fall back to (a) only with an explicit
written statement of what it widens."* The famous *"a real widening of `db`'s reachable-from set on an
axis the RT-32 fence cannot see"* clause describes **(a)** — Coolify's `connect_to_docker_network`
toggle — specifically. An `external:` network declared in a committed compose is **(b)**, which A4
describes as attaching *"exactly one new member"*. **A PR using (b) discharges no A4 statement
obligation**, and citing A4 to demand one is mis-siting the quote.

**Why:** in the PR #844 review both of these arrived as glosses — one in my own role brief's veto
list, one in the dispatch brief — and both read as authoritative. Acting on either would have
produced a veto against a PR executing ADR-073 Decision A, which names `etl`, `pdf-render` and
`provider-sync` by name as the ratified fleet convention (Accepted, F/CTO 2026-09-19).

**How to apply:** when a proposal touches worker network attachment or PDF-worker DB reach, quote
these two predicates from their own sources before grading. The statement that IS still owed when a
widening happens is the ADR-073 Consequence 4 shape — a plain re-grading of any previously ACCEPTED
residual whose grounds the widening falsifies — not an A4 obligation.
See [[sec-lock-cross-check-catches-my-own-misreads]] and
[[an-accepted-residual-must-not-silently-widen]].
