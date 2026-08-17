---
name: cited-precedent-transmits-its-retracted-half
description: Citing a precedent's rationale imports whatever that precedent later corrected about itself — read the amendments attached to what you cite, not just the passage
metadata:
  type: feedback
---

When I cite an earlier instance's rationale, I inherit **its retracted claims along with
its live ones** unless I read the corrections appended to it.

**Why:** at `074` (#17) I wrote that the fence's cross-tenant leg was *"reachable only by
an RLS-EXEMPT writer,"* citing ADR-042 Decision 5a — #16's rationale. **ADR-042 itself
already contains Sec's narrowing of exactly that claim** for #16: *"correct but broader
than the facts"* — an ownership forge from a plain `authenticated` caller trips the leg
too, because the referenced row genuinely resolves and only the tenant comparison rejects
it. I read the passage I was citing and not the amendment sitting a few hundred lines
below it, so I reproduced the retracted half verbatim into three artifacts plus a catalog
comment. QA caught it empirically.

**How to apply:** before citing an ADR decision as authority, grep that ADR for later text
about the same instance — amendments, corrections, fold-in resolutions, Consequences
blocks. In this repo they are appended below rather than folded into the original, so the
passage you land on is frequently the *pre-correction* one. The tell that should trigger
the check: a citation carrying the words *only*, *never*, or *always* about reachability or
coverage. Related: [[replacement-control-name-the-losing-side]] and
[[verifying-a-measurement-is-not-verifying-a-claim]] — and the fix here is the same shape,
ask what the procedure could not see.
