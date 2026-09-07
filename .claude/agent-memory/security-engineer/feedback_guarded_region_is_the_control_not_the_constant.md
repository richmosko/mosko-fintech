---
name: guarded-region-is-the-control-not-the-constant
description: When a module claims to mirror a sibling transport, diff the REGION BOUNDARIES (what the try/finally/abort actually covers), not the constants; and rule an OPEN by testing each stated rationale against the OTHER controls' criteria.
metadata:
  type: feedback
---

**Two lessons from SELF-349 / A5 (`renderClient.ts`, PR #638, 2026-09-05).**

**1. A "mirrors <sibling>" claim is a claim about REGION BOUNDARIES, not about constants.**
The module matched `admissionClient.ts` on every visible token — `AbortController`, `TIMEOUT_MS`,
`clearTimeout` in a `finally`, status-only logging, the `{ok,status}` result shape — and diverged
on the one thing that is not a token: the sibling reads its response body **inside** the guarded
`try`; this one closed the `try` at `fetch` and read the body after. Result: the 30 s timeout
bounded only the header phase, and a mid-body error threw out of a function whose own header
promised it never throws.

**Why:** `fetch` resolves at headers. Every property a reviewer attributes to "the timeout" —
bounded duration, abort on stall, errors mapped to a result — is a property of *what the guarded
region encloses*, and a diff of the constants cannot see it.

**How to apply:** on any `fetch`/transport review, ask three questions in this order — what does
the `try` enclose? what is still armed when the body is read? which awaits are outside the
`catch`? Then diff those answers against the sibling the module names. A claimed convention is a
falsifiable claim; check it at the boundary, not at the identifier.

**2. Rule an `⟨OPEN⟩` by testing each stated rationale against the OTHER controls' criteria first.**
A5's `users_id`-vs-opaque-id OPEN offered "forensic value at the worker" as the reason to keep the
tenant claim. That rationale was already **foreclosed** — the worker's rejection signal is keyed on
a fixed reason enum and carries no request content, because ADR-050 D4's criterion forbids
attacker-controlled content and R-6's shipped form implements it that way. So the argument rested
on a capability the tree forbids adding. The ruling (keep) survived, but on entirely different
grounds, and the module's stated reasoning had to be corrected as part of the ruling.

**How to apply:** before weighing an OPEN's options, run each *stated* rationale against every
control it touches and mark it live / foreclosed. Then rule on what is left. A ruling that adopts
a proposal's reasoning wholesale inherits its dead premises — and they ship as the receiving
file's own claims. See [[feedback_my_review_measurements_become_quoted_sources]] and
[[feedback_hazard_mechanism_vs_reachability]].
