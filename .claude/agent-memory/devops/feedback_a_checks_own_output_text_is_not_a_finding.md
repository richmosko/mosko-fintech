---
name: a-checks-own-output-text-is-not-a-finding
description: quoting a defective check's own hardcoded message string as an adjudicated finding, instead of verifying the claim it makes
metadata:
  type: feedback
---

Never cite a script/check's own printed message text (e.g. "a live RLS bypass, not a fixture artifact") as an established finding when writing it into a ledger, PR body, or memory. That text is a claim BY the tool, and inherits every defect the tool has — a bare `count(*)`-based check cannot distinguish a design-intended global row (e.g. `users_id IS NULL`, visible to everyone by ADR-060) from an actual tenant-row leak, so its own "bypass" language can be flat wrong even while it looks confidently adjudicated.

**Why:** self-caught + Sec-corrected on PR #882 (2026-09-22): I read run 27's raw log, saw `pfin.asset: 7 row(s) visible ... "a live RLS bypass, not a fixture artifact"`, and wrote that verbatim into standup-log.md/MILESTONES.md/the PR body as an open, unconfirmed finding. Sec had already ruled it design-by-ADR-060 (team-lead's own discriminating query measured `leaked=0, global=7` on the box) — the quoted text was the DEFECTIVE check's own message (fixed in PR #883's hybrid-aware assertion), not a verified security claim. Same shape as an earlier incident that session: a script header asserting a key was "never in any process's argv," which propagated unverified through three people.

**How to apply:** when a log/check emits a confident security-sounding disclaimer ("not a fixture artifact", "genuine", "confirmed live"), treat that STRING as the thing needing verification, not as evidence to relay. Before writing it into a durable record: (1) check whether someone with standing to rule (Sec/Architect) has already adjudicated it — ask, don't assume silence means unconfirmed; (2) if citing it for visibility before confirmation is warranted, frame it explicitly as "the tool's own unverified claim," never drop the hedge; (3) once a ruling lands that contradicts the tool's own text, correct every location that quoted it, not just the primary one — a milestone ledger, a PR body, and a standup log can each carry an independent stale copy.
