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

**Second instance, 2026-09-04 (SELF-262 / `104` + ADR-067) — the same rule, but the
citation was not to a retracted claim; it was to the WRONG HOME.** Two team-lead records
(V1.4 execution log E22 and sitting-log R3 rider 6) both gloss the principle as *"ADR-049
rendered-not-silent."* ADR-049 Decision 5 **disowns that attribution in its own text**: the
non-silent-staleness framework is **PRD §2.4.4 per ADR-013**, and that Decision carries an
explicit ⚠ *"Citation accuracy, recorded because the mis-citation nearly landed"* note on
this exact principle. I wrote the gloss into a migration header and an ADR first, caught it
only because I opened ADR-049 to check the pointer, and corrected both before committing.

**What generalizes:** a gloss repeated across the project's own records reads as settled
vocabulary and invites zero checking — **repetition is not corroboration when every copy
has one source.** And the check that catches it is cheap and specific: open the cited ADR
and look for whether it names a DIFFERENT artifact as the principle's home. An ADR that
*routes to* a framework is not that framework's home, and consuming it as one silently
reassigns authorship.
