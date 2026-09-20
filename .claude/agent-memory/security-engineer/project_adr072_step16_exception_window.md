---
name: adr072-step16-exception-window
description: The dated one-time exception to apply-migration Step 1.6 was opened AND widened twice on 2026-09-16; it expires when the re-bootstrap lands and a deployment survives. Check its state before citing it, and treat a third widening as an escalation.
metadata:
  type: project
---

**A dated one-time exception to `apply-migration` Step 1.6 is OPEN, permitting executable edits to already-applied
migrations `001`–`118` (plus `007`/`015`). It lives in `.claude/skills/apply-migration/SKILL.md` and is mirrored
by a table in ADR-072 Amendment 5 — the two must name the same set.**

**Why:** F/CTO ruled the `001`–`118` apply DISPOSABLE (never deployed, no data, box wiped and re-bootstrapped),
which voids Step 1.6's *"already applied"* premise **for that window only**. **It EXPIRES when the re-bootstrap
lands and a deployment survives** — after that Step 1.6 governs again unamended and the block is history, not
authority.

**How to apply:**
- **Read its live state before citing it — never from this memory.** It was **opened 2026-09-16 and widened
  TWICE the same day** (once for the whole-unit `007`/`015` guard, once for the `117`/`118`/`119` `comment on
  role` dispositions). A tripwire is built in: **a third widening should prompt asking F/CTO whether it still
  describes one bounded window.** That prompt is a QUESTION TO F/CTO, never a note that clears itself.
- **Widening the Scope is F/CTO's act** — not Architect's, not Sec's. An edit to an applied migration that is not
  on the named list is uncovered, however reasonable it looks.
- **Check both representations in the same read.** Correcting one and leaving the twin stale recurred three times
  in this workstream before the final pin fixed both in one commit — see
  [[correcting-half-a-hand-maintained-mirror]].
- At any ratify or widening, verify the **EXPIRES** clause, the **does-NOT-cover** bullet and the *"EXCEPTION,
  not a precedent"* opener survived. A tiny diff (`+1/-1`) is arithmetic proof; a larger one needs reading.
