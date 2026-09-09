---
name: 365-v1final-protocol
description: SELF-365 (P11, V1.final §3.4 close-gate) — F/CTO ruled all seven items 2026-09-07; record finalized on feature/self-365 @6949dc88 (PR #661 draft) with six copy-ready sub-issue specs; what PM still owes (PRD amendment PR P-1/P-2/P-3) and the traps found.
metadata:
  type: project
---

**State (2026-09-07, round 2):** `docs/records/v1final/self365-protocol.md` on `feature/self-365` @ `6949dc88` (base `d83d7edb`, draft PR #661) carries §G (rulings) + §H (dispatch list) and six FINAL sub-issue specs: B.1 (a) A-3 · B.2 (b) B-2+S-2 · B.3 (c)×2 · B.4 close-PR · B.5 Production stand-up (Phase 7 entry, DevOps, no parent). WORKFLOW Phase 6 exit clause amended ("…except the calendar-gated V1.final close-gate, which closes in Phase 7"). BACKLOG §5.6 (SELF-375 M-1) + §7.35 landed. 3 `⟨OPEN⟩` remain, all DevOps, all in B.5.

**Rulings in one line each:** (1) Phase 7 starts now in parallel; month-1 = first full month after tenant accounts live in prod. (2) A-3: manual §2.6 comparison on deploy month M0; Backend M0 completeness check is a named Dependency BEFORE (a) is created. (3) B-2 + S-2: security-catalog (b) re-homed to Phase 6 exit walk. (4) account added mid-M doesn't break clause (1); on_demand month doesn't count. (5) clause (4) = attestation + retained file. (6) SELF-375 wording ratified; M-3 carrier; M-1 → §5.6. (7) SELF-378 T-1 pinned on SELF-351; T-3 → §7.35; PRD §7.3 amendment booked.

**Why it matters / how to apply:** PM OWES the PRD amendment PR (§H P-1 §3.4(a)(ii), P-2 §3.4(b), P-3 §7.3 + the three "V1 ships to a single user" story sentences at §2.1/§2.2/§2.3) — merged BEFORE (a)/(b) close; it cites Architect's terse ADR (§7.35 item 3), so ADR first. (a) is NOT created at the initial liaison batch — only after Backend's `a-m0-completeness.md` exists (post-stand-up). `role:devops` label is ABSENT in Linear (docs/linear-setup.md) — F/CTO must create it before B.5. The deploy target month was NOT ruled; B.5 derives M0/M1 from recorded dates. §7.34 had landed with no §7 index row (fixed here) — check the index at every §7 append. Precedent shape: [[v15-preflight-recalibration]].
